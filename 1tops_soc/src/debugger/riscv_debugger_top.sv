//-----------------------------------------------------------------------------
// Top-Level Debugger Subsystem for CORE-V Wally RISC-V SoC
// Integrates:
//   - Dedicated UART Transceiver (socdebug_uart.v)
//   - Dedicated FT1248 Transceiver (socdebug_ft1248_control.v)
//   - Physical Protocol Selection Mux (dbg_sel pin: 0=UART, 1=FT1248)
//   - ASCII Debug Protocol (ADP) AHB-Lite Master Controller (socdebug_ahb.v)
//   - Hardware Core Halt / Resume / Reset pipeline hooks
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module riscv_debugger_top #(
    parameter CLK_FREQ    = 50_000_000,
    parameter BAUD_RATE   = 115200,
    parameter PROMPT_CHAR = "]",
    parameter FT_WIDTH    = 1,
    parameter FT_CLKDIV   = 8'd2
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Communication Protocol Selection Pin (Physical hardware pad)
    // 0 = Dedicated Debug UART
    // 1 = Dedicated FT1248 High-Speed Interface
    input  wire                 dbg_sel,

    // UART Physical Interface
    input  wire                 uart_rx,
    output wire                 uart_tx,

    // FT1248 Physical Interface
    output wire                 ft1248_clk,     // SCLK output to FTDI
    output wire                 ft1248_ss_n,    // SS_N output to FTDI
    input  wire                 ft1248_miso,    // MISO input from FTDI (RXF# status)
    inout  wire [FT_WIDTH-1:0]  ft1248_miosio,  // Bi-directional data (TXE# status when idle)

    // Core Control & Status Signals
    output wire                 core_halt_o,    // Connect to ExternalStall of RISC-V Core
    output wire                 core_reset_o,   // System / Core Reset request
    input  wire                 core_halted_i,  // Core Halted status feedback from Hazard unit

    // AHB-Lite Master Interface (Connect to AHB Mux/Arbiter)
    output wire [31:0]          DEBUG_HADDR,
    output wire [ 2:0]          DEBUG_HBURST,
    output wire                 DEBUG_HMASTLOCK,
    output wire [ 3:0]          DEBUG_HPROT,
    output wire [ 2:0]          DEBUG_HSIZE,
    output wire [ 1:0]          DEBUG_HTRANS,
    output wire [31:0]          DEBUG_HWDATA,
    output wire                 DEBUG_HWRITE,
    input  wire [31:0]          DEBUG_HRDATA,
    input  wire                 DEBUG_HREADY,
    input  wire                 DEBUG_HRESP,

    // Raw GPIO (optional monitor)
    output wire [7:0]           GPO8,
    input  wire [7:0]           GPI8
);

    //-------------------------------------------------------------------------
    // 1. Dedicated Debug UART Transceiver Streams
    //-------------------------------------------------------------------------
    wire [7:0] uart_adp_rx_data;
    wire       uart_adp_rx_valid;
    wire       uart_adp_rx_ready;

    wire [7:0] uart_adp_tx_data;
    wire       uart_adp_tx_valid;
    wire       uart_adp_tx_ready;

    socdebug_uart #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx),
        .uart_tx       (uart_tx),
        .m_axis_tdata  (uart_adp_rx_data),
        .m_axis_tvalid (uart_adp_rx_valid),
        .m_axis_tready (uart_adp_rx_ready),
        .s_axis_tdata  (uart_adp_tx_data),
        .s_axis_tvalid (uart_adp_tx_valid),
        .s_axis_tready (uart_adp_tx_ready)
    );

    //-------------------------------------------------------------------------
    // 2. Dedicated FT1248 Transceiver Streams & Tristate IO Buffers
    //-------------------------------------------------------------------------
    wire [7:0] ft_adp_rx_data;
    wire       ft_adp_rx_valid;
    wire       ft_adp_rx_ready;

    wire [7:0] ft_adp_tx_data;
    wire       ft_adp_tx_valid;
    wire       ft_adp_tx_ready;

    wire [FT_WIDTH-1:0] ft_miosio_o;
    wire [FT_WIDTH-1:0] ft_miosio_e;
    wire [FT_WIDTH-1:0] ft_miosio_i;

    genvar g;
    generate
        for (g = 0; g < FT_WIDTH; g = g + 1) begin : gen_miosio_buf
            assign ft1248_miosio[g] = (ft_miosio_e[g]) ? ft_miosio_o[g] : 1'bz;
            assign ft_miosio_i[g]   = ft1248_miosio[g];
        end
    endgenerate

    socdebug_ft1248_control #(
        .FT1248_WIDTH (FT_WIDTH),
        .FT1248_CLKON (1)
    ) u_ft1248 (
        .clk         (clk),
        .resetn      (rst_n),
        .ft_clkdiv   (FT_CLKDIV),
        .ft_clk_o    (ft1248_clk),
        .ft_ssn_o    (ft1248_ss_n),
        .ft_miso_i   (ft1248_miso),
        .ft_miosio_o (ft_miosio_o),
        .ft_miosio_e (ft_miosio_e),
        .ft_miosio_z (),
        .ft_miosio_i (ft_miosio_i),

        // ADP Interface - Data coming from FTDI to ADP
        .txd_tvalid  (ft_adp_rx_valid),
        .txd_tdata   (ft_adp_rx_data),
        .txd_tready  (ft_adp_rx_ready),
        .txd_tlast   (),

        // ADP Interface - Data from ADP going to FTDI
        .rxd_tvalid  (ft_adp_tx_valid),
        .rxd_tdata   (ft_adp_tx_data),
        .rxd_tready  (ft_adp_tx_ready),
        .rxd_tlast   (1'b0)
    );

    //-------------------------------------------------------------------------
    // 3. 2-to-1 Protocol Stream Multiplexer (Controlled by dbg_sel pin)
    //    dbg_sel == 1'b0: Select UART
    //    dbg_sel == 1'b1: Select FT1248
    //-------------------------------------------------------------------------
    wire [7:0] adp_rxd_data;
    wire       adp_rxd_valid;
    wire       adp_rxd_ready;

    wire [7:0] adp_txd_data;
    wire       adp_txd_valid;
    wire       adp_txd_ready;

    // Rx Stream (Host -> ADP Controller)
    assign adp_rxd_data      = (dbg_sel) ? ft_adp_rx_data  : uart_adp_rx_data;
    assign adp_rxd_valid     = (dbg_sel) ? ft_adp_rx_valid : uart_adp_rx_valid;

    // Backpressure routing: Only the active transceiver receives ready from ADP
    assign uart_adp_rx_ready = (!dbg_sel) ? adp_rxd_ready : 1'b0;
    assign ft_adp_rx_ready   = ( dbg_sel) ? adp_rxd_ready : 1'b0;

    // Tx Stream (ADP Controller -> Host)
    assign uart_adp_tx_data  = adp_txd_data;
    assign ft_adp_tx_data    = adp_txd_data;

    // Valid routing: Only the active transceiver receives valid from ADP
    assign uart_adp_tx_valid = (!dbg_sel) ? adp_txd_valid : 1'b0;
    assign ft_adp_tx_valid   = ( dbg_sel) ? adp_txd_valid : 1'b0;

    assign adp_txd_ready     = (dbg_sel) ? ft_adp_tx_ready : uart_adp_tx_ready;

    //-------------------------------------------------------------------------
    // 4. Instantiate SoCDebug AHB Master Controller
    //-------------------------------------------------------------------------
    socdebug_ahb #(
        .PROMPT_CHAR (PROMPT_CHAR)
    ) u_socdebug_ahb (
        .HCLK           (clk),
        .HRESETn        (rst_n),
        .HADDR32_o      (DEBUG_HADDR),
        .HBURST3_o      (DEBUG_HBURST),
        .HMASTLOCK_o    (DEBUG_HMASTLOCK),
        .HPROT4_o       (DEBUG_HPROT),
        .HSIZE3_o       (DEBUG_HSIZE),
        .HTRANS2_o      (DEBUG_HTRANS),
        .HWDATA32_o     (DEBUG_HWDATA),
        .HWRITE_o       (DEBUG_HWRITE),
        .HRDATA32_i     (DEBUG_HRDATA),
        .HREADY_i       (DEBUG_HREADY),
        .HRESP_i        (DEBUG_HRESP),

        // Stream Interface connected to the Protocol Multiplexer
        .COMRX_TDATA_i  (adp_rxd_data),
        .COMRX_TVALID_i (adp_rxd_valid),
        .COMRX_TREADY_o (adp_rxd_ready),
        .COMTX_TDATA_o  (adp_txd_data),
        .COMTX_TVALID_o (adp_txd_valid),
        .COMTX_TREADY_i (adp_txd_ready),

        // Unused STDIO stream tied off
        .STDTX_TVALID_o (),
        .STDTX_TDATA_o  (),
        .STDTX_TREADY_i (1'b1),
        .STDRX_TVALID_i (1'b0),
        .STDRX_TDATA_i  (8'h00),
        .STDRX_TREADY_o (),

        // Core Control & Status
        .core_halt_o    (core_halt_o),
        .core_reset_o   (core_reset_o),
        .core_halted_i  (core_halted_i),

        .GPO8_o         (GPO8),
        .GPI8_i         (GPI8)
    );

endmodule
