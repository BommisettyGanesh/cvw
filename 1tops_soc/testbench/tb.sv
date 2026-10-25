module tb(
  input logic clk,
  input logic reset
);
  import cvw::*;
  `include "config.vh"
  `include "parameter-defs.vh"

  // External AHB Interface
  logic                reset_sync;
  logic                HCLK, HRESETn;
  logic [P.PA_BITS-1:0] HADDREXT;
  logic [P.AHBW-1:0]    HWDATATAEXT;
  logic [P.XLEN/8-1:0]  HWSTRBEXT;
  logic                HWRITEEXT;
  logic [2:0]          HSIZEEXT;
  logic [2:0]          HBURSTEXT;
  logic [3:0]          HPROTEXT;
  logic [1:0]          HTRANSEXT;
  logic                HMASTLOCKEXT;
  logic                HREADYEXT;

  // Peripheral Interface Signals
  logic [31:0]         GPIOOUT, GPIOEN;
  logic                UARTSout;
  logic                SPIOut;
  logic [3:0]          SPICS;
  logic                SPICLK;
  logic                SDCCmd;
  logic [3:0]          SDCCS;
  logic                SDCCLK;

  // Debugger Interface Signals
  logic                uart_tx;
  logic                ft1248_clk, ft1248_ss_n;
  wire  [0:0]          ft1248_miosio;
  logic                core_halted_led;

  // SoC Instantiation
  wallypipelinedsoc #(P) soc (
    .clk              (clk),
    .reset_ext        (reset),
    .reset            (reset_sync),
    .ExternalStall    (1'b0),
    .HCLK             (HCLK),
    .HRESETn          (HRESETn),
    .HADDR            (HADDREXT),
    .HWDATA           (HWDATATAEXT),
    .HWSTRB           (HWSTRBEXT),
    .HWRITE           (HWRITEEXT),
    .HSIZE            (HSIZEEXT),
    .HBURST           (HBURSTEXT),
    .HPROT            (HPROTEXT),
    .HTRANS           (HTRANSEXT),
    .HMASTLOCK        (HMASTLOCKEXT),
    .HREADY           (HREADYEXT),
    .TIMECLK          (1'b0),
    .GPIOIN           (32'h0),
    .GPIOOUT          (GPIOOUT),
    .GPIOEN           (GPIOEN),
    .UARTSin          (1'b1), // UART idle high
    .UARTSout         (UARTSout),
    .SPIIn            (1'b0),
    .SPIOut           (SPIOut),
    .SPICS            (SPICS),
    .SPICLK           (SPICLK),
    .SDCIn            (1'b0),
    .SDCCmd           (SDCCmd),
    .SDCCS            (SDCCS),
    .SDCCLK           (SDCCLK),
    .dbg_sel          (1'b0),
    .uart_rx          (1'b1),
    .uart_tx          (uart_tx),
    .ft1248_clk       (ft1248_clk),
    .ft1248_ss_n      (ft1248_ss_n),
    .ft1248_miso      (1'b1),
    .ft1248_miosio    (ft1248_miosio),
    .core_halted_led  (core_halted_led)
  );

endmodule
