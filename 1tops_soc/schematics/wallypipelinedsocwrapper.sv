///////////////////////////////////////////
// wallypipelinedsocwrapper.sv
//
// Dynamic Top-level wrapper for Vivado Schematic Elaboration
// Reads parameters dynamically from config/config.vh & config/parameter-defs.vh
////////////////////////////////////////////

`include "config.vh"

import cvw::*;

`include "parameter-defs.vh"

module wallypipelinedsocwrapper #(
  parameter CLK_FREQ    = 100_000_000,
  parameter BAUD_RATE   = 115200,
  parameter PROMPT_CHAR = "]",
  parameter FT_WIDTH    = 1,
  parameter FT_CLKDIV   = 8'd4
) (
  input  logic                clk,
  input  logic                reset_ext,        // external asynchronous reset pin
  output logic                reset,            // reset synchronized to clk
  // fpga debug signals
  input  logic                ExternalStall,
  // outputs to external memory, shared with uncore memory
  output logic                HCLK, HRESETn,
  output logic [P.PA_BITS-1:0]  HADDR,
  output logic [P.AHBW-1:0]     HWDATA,
  output logic [P.XLEN/8-1:0]   HWSTRB,
  output logic                HWRITE,
  output logic [2:0]          HSIZE,
  output logic [2:0]          HBURST,
  output logic [3:0]          HPROT,
  output logic [1:0]          HTRANS,
  output logic                HMASTLOCK,
  output logic                HREADY,
  // I/O Interface
  input  logic                TIMECLK,          // optional for CLINT MTIME counter
  input  logic [31:0]         GPIOIN,           // inputs from GPIO
  output logic [31:0]         GPIOOUT,          // output values for GPIO
  output logic [31:0]         GPIOEN,           // output enables for GPIO
  input  logic                UARTSin,          // UART serial data input
  output logic                UARTSout,         // UART serial data output
  input  logic                SPIIn,            // SPI pins in
  output logic                SPIOut,           // SPI pins out
  output logic [3:0]          SPICS,            // SPI chip select pins
  output logic                SPICLK,           // SPI clock
  input  logic                SDCIn,            // SDC DATA[0]
  output logic                SDCCmd,           // SDC CMD
  output logic [3:0]          SDCCS,            // SDC Card Detect
  output logic                SDCCLK,           // SDC Clock

  // Dual-Protocol Debugger Hardware Pins
  input  logic                dbg_sel         = 1'b0,
  input  logic                uart_rx         = 1'b1,
  output logic                uart_tx,
  output logic                ft1248_clk,
  output logic                ft1248_ss_n,
  input  logic                ft1248_miso     = 1'b1,
  inout  wire [FT_WIDTH-1:0]  ft1248_miosio,
  output logic                core_halted_led
);

  // Instantiates top SoC module dynamically with parameters P derived from config.vh
  wallypipelinedsoc #(
    .P           (P),
    .CLK_FREQ    (CLK_FREQ),
    .BAUD_RATE   (BAUD_RATE),
    .PROMPT_CHAR (PROMPT_CHAR),
    .FT_WIDTH    (FT_WIDTH),
    .FT_CLKDIV   (FT_CLKDIV)
  ) soc (.*);

endmodule
