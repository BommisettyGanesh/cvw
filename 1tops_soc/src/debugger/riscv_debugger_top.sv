//-----------------------------------------------------------------------------
// Top-Level Debugger Subsystem for CORE-V Wally RISC-V SoC
// Redesigned to transfer data to/from the UART present in uncore
// Replaces dedicated UART transceiver (socdebug_uart) with direct uncore UART interface
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module riscv_debugger_top #(
    parameter PROMPT_CHAR = "]"
)(
    input  wire        clk,
    input  wire        rst_n,

    // Interface to Uncore UART (Transfers data to/from existing uncore UART)
    input  wire [7:0]  uart_rx_data,
    input  wire        uart_rx_valid,
    output wire        uart_rx_ready,

    output wire [7:0]  uart_tx_data,
    output wire        uart_tx_valid,
    input  wire        uart_tx_ready,

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

        // Stream Interface connected directly to Uncore UART data transfer ports
        .COMRX_TDATA_i  (uart_rx_data),
        .COMRX_TVALID_i (uart_rx_valid),
        .COMRX_TREADY_o (uart_rx_ready),
        .COMTX_TDATA_o  (uart_tx_data),
        .COMTX_TVALID_o (uart_tx_valid),
        .COMTX_TREADY_i (uart_tx_ready),

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
