////////////////////////////////////////////////////////////////////////////////
// wallypipelinedsoc.sv
//
// Top-Level SoC module for 1tops_soc, powered by the verified
// 5-stage pipelined RV32I SoC (riscv_soc_ahb)
////////////////////////////////////////////////////////////////////////////////

`include "config.vh"
import cvw::*;
`include "parameter-defs.vh"

module wallypipelinedsoc import cvw::*; #(
  parameter cvw_t P,
  parameter CLK_FREQ    = 100_000_000,
  parameter BAUD_RATE   = 115200,
  parameter PROMPT_CHAR = "]",
  parameter FT_WIDTH    = 1,
  parameter FT_CLKDIV   = 8'd4
) (
  input  logic                clk,
  input  logic                reset_ext,        // external asynchronous reset pin
  output logic                reset,            // reset synchronized to clk
  input  logic                ExternalStall,
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
  input  logic                TIMECLK,
  input  logic [31:0]         GPIOIN,
  output logic [31:0]         GPIOOUT,
  output logic [31:0]         GPIOEN,
  input  logic                UARTSin,
  output logic                UARTSout,
  input  logic                SPIIn,
  output logic                SPIOut,
  output logic [3:0]          SPICS,
  output logic                SPICLK,
  input  logic                SDCIn,
  output logic                SDCCmd,
  output logic [3:0]          SDCCS,
  output logic                SDCCLK,

  // Dual-Protocol Debugger Hardware Pins
  input  logic                dbg_sel,
  input  logic                uart_rx,
  output logic                uart_tx,
  output logic                ft1248_clk,
  output logic                ft1248_ss_n,
  input  logic                ft1248_miso,
  inout  wire [FT_WIDTH-1:0]  ft1248_miosio,
  output logic                core_halted_led
);

  // Synchronize reset to SoC clock domain
  synchronizer resetsync(.clk(clk), .d(reset_ext), .q(reset));

  assign HCLK    = clk;
  assign HRESETn = ~reset;

  // Top-Level Unified RISC-V SoC Instance
  riscv_soc_ahb #(
    .RESET_PC        (P.RESET_VECTOR[31:0]),
    .MEM_SIZE_BYTES  (16384)
  ) soc_i (
    .clk             (clk),
    .reset           (reset),
    .MExtInt         (1'b0),
    .TrapM           (),
    .mretM           (),
    .PCW             (),
    .ResultW         (),
    .GPIOIN          (GPIOIN),
    .GPIOOUT         (GPIOOUT),
    .GPIOEN          (GPIOEN),
    .UARTSin         (UARTSin),
    .UARTSout        (UARTSout),
    .SPIIn           (SPIIn),
    .SPIOut          (SPIOut),
    .SPICS           (SPICS),
    .SPICLK          (SPICLK),
    .dbg_sel         (dbg_sel),
    .uart_rx         (uart_rx),
    .uart_tx         (uart_tx),
    .ft1248_clk      (ft1248_clk),
    .ft1248_ss_n     (ft1248_ss_n),
    .ft1248_miso     (ft1248_miso),
    .ft1248_miosio   (ft1248_miosio),
    .core_halted_led (core_halted_led)
  );

  assign HADDR        = '0;
  assign HWDATA       = '0;
  assign HWSTRB       = '0;
  assign HWRITE       = 1'b0;
  assign HSIZE        = 3'b0;
  assign HBURST       = 3'b0;
  assign HPROT        = 4'b0;
  assign HTRANS       = 2'b0;
  assign HMASTLOCK    = 1'b0;
  assign HREADY       = 1'b1;
  assign SDCCmd       = 1'b0;
  assign SDCCS        = 4'b0;
  assign SDCCLK       = 1'b0;

endmodule
