//-----------------------------------------------------------------------------
// Top-Level Debugger Subsystem for CORE-V Wally RISC-V SoC
// Integrates UART Transceiver, ADP Controller, Core Halt/Resume hooks,
// and AHB-Lite Master Interface
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module riscv_debugger_top #(
    parameter CLK_FREQ    = 50_000_000,
    parameter BAUD_RATE   = 115200,
    parameter PROMPT_CHAR = "]"
)(
    input  wire        clk,
    input  wire        rst_n,

    // UART Physical Interface
    input  wire        uart_rx,
    output wire        uart_tx,

    // Core Control & Status Signals
    output wire        core_halt_o,    // Connect to ExternalStall of RISC-V Core
    output wire        core_reset_o,   // System / Core Reset request
    input  wire        core_halted_i,  // Core Halted status feedback from Hazard unit

    // AHB-Lite Master Interface (Connect to AHB Mux/Arbiter)
    output wire [31:0] DEBUG_HADDR,
    output wire [ 2:0] DEBUG_HBURST,
    output wire        DEBUG_HMASTLOCK,
    output wire [ 3:0] DEBUG_HPROT,
    output wire [ 2:0] DEBUG_HSIZE,
    output wire [ 1:0] DEBUG_HTRANS,
    output wire [31:0] DEBUG_HWDATA,
    output wire        DEBUG_HWRITE,
    input  wire [31:0] DEBUG_HRDATA,
    input  wire        DEBUG_HREADY,
    input  wire        DEBUG_HRESP,

    // Raw GPIO (optional monitor)
    output wire [7:0]  GPO8,
    input  wire [7:0]  GPI8
);

    // Internal Stream connections between UART and ADP controller
    wire [7:0] adp_rxd_data;
    wire       adp_rxd_valid;
    wire       adp_rxd_ready;

    wire [7:0] adp_txd_data;
    wire       adp_txd_valid;
    wire       adp_txd_ready;

    // Instantiate UART Transceiver
    socdebug_uart #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx),
        .uart_tx       (uart_tx),
        .m_axis_tdata  (adp_rxd_data),
        .m_axis_tvalid (adp_rxd_valid),
        .m_axis_tready (adp_rxd_ready),
        .s_axis_tdata  (adp_txd_data),
        .s_axis_tvalid (adp_txd_valid),
        .s_axis_tready (adp_txd_ready)
    );

    // Instantiate SoCDebug AHB Controller
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

        // Stream Interface connected to UART
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
