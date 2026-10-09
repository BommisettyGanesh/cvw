////////////////////////////////////////////////////////////////////////////////
// wally_soc_fpga_top.sv
//
// Dedicated Top-Level FPGA Wrapper for CORE-V Wally RISC-V SoC with
// Dual-Protocol Hardware Debugger on Digilent Basys 3 (Artix-7 xc7a35tcpg236-1)
////////////////////////////////////////////////////////////////////////////////

`include "config.vh"
import cvw::*;
`include "parameter-defs.vh"

module wally_soc_fpga_top #(
  parameter CLK_FREQ    = 100_000_000, // Basys 3 100 MHz onboard oscillator
  parameter BAUD_RATE   = 115200,      // Debugger UART baud rate
  parameter PROMPT_CHAR = "]",         // ADP CLI prompt
  parameter FT_WIDTH    = 1,           // FT1248 bus width (1-bit on Basys 3 PMOD JB)
  parameter FT_CLKDIV   = 8'd4          // 100 MHz / (2 * (4 + 1)) = 10 MHz FT1248 clock
) (
  // 1. Clock and Reset (Basys 3 Onboard)
  input  logic                clk,              // 100 MHz on-board oscillator (Pin W5)
  input  logic                reset_btn,        // Pushbutton btnC (Pin U18 - Active High)

  // 2. Dual-Protocol Hardware Debugger Pins
  input  logic                dbg_sel,          // Slide Switch SW0 (Pin V17: 0=UART, 1=FT1248)
  input  logic                uart_rx,          // PMOD JA Pin 1 (Pin J1: from host PC)
  output logic                uart_tx,          // PMOD JA Pin 2 (Pin L2: to host PC)
  output logic                ft1248_clk,       // PMOD JB Pin 1 (Pin A14: SCLK to FT232H)
  output logic                ft1248_ss_n,      // PMOD JB Pin 2 (Pin A16: SS# to FT232H)
  input  logic                ft1248_miso,      // PMOD JB Pin 3 (Pin B15: MISO / RXF# from FT232H)
  inout  wire [FT_WIDTH-1:0]  ft1248_miosio,    // PMOD JB Pin 4 (Pin B16: MIOSIO Data Bus)

  // 3. Uncore Application 16550 UART (Onboard Micro-USB Port)
  input  logic                UARTSin,          // USB-UART RX (Pin B18: PC -> SoC)
  output logic                UARTSout,         // USB-UART TX (Pin A18: SoC -> PC)

  // 4. Status LEDs
  output logic                led_core_halted,  // LED 0 (Pin U16: Lit when CPU is halted)
  output logic                led_dbg_sel       // LED 1 (Pin E19: Reflects SW0 dbg_sel state)
);

  // Active-low external reset conversion for SoC
  wire reset_ext = ~reset_btn;

  // Visual status LED for protocol switch
  assign led_dbg_sel = dbg_sel;

  // Unused peripheral ties
  wire        ExternalStall = 1'b0;
  wire        TIMECLK       = 1'b0;
  wire [31:0] GPIOIN        = 32'b0;
  wire [31:0] GPIOOUT;
  wire [31:0] GPIOEN;
  wire        SPIIn         = 1'b0;
  wire        SPIOut;
  wire [3:0]  SPICS;
  wire        SPICLK;
  wire        SDCIn         = 1'b0;
  wire        SDCCmd;
  wire [3:0]  SDCCS;
  wire        SDCCLK;
  wire        HCLK, HRESETn;
  wire [P.PA_BITS-1:0] HADDR;
  wire [P.AHBW-1:0]    HWDATA;
  wire [P.XLEN/8-1:0]  HWSTRB;
  wire                 HWRITE;
  wire [2:0]           HSIZE, HBURST;
  wire [3:0]           HPROT;
  wire [1:0]           HTRANS;
  wire                 HMASTLOCK, HREADY, reset;

  // Instantiate complete SoC with integrated Dual-Protocol Debugger & BRAM memories
  wallypipelinedsoc #(
    .P           (P),
    .CLK_FREQ    (CLK_FREQ),
    .BAUD_RATE   (BAUD_RATE),
    .PROMPT_CHAR (PROMPT_CHAR),
    .FT_WIDTH    (FT_WIDTH),
    .FT_CLKDIV   (FT_CLKDIV)
  ) soc (
    .clk              (clk),
    .reset_ext        (reset_ext),
    .reset            (reset),
    .ExternalStall    (ExternalStall),
    .HCLK             (HCLK),
    .HRESETn          (HRESETn),
    .HADDR            (HADDR),
    .HWDATA           (HWDATA),
    .HWSTRB           (HWSTRB),
    .HWRITE           (HWRITE),
    .HSIZE            (HSIZE),
    .HBURST           (HBURST),
    .HPROT            (HPROT),
    .HTRANS           (HTRANS),
    .HMASTLOCK        (HMASTLOCK),
    .HREADY           (HREADY),
    .TIMECLK          (TIMECLK),
    .GPIOIN           (GPIOIN),
    .GPIOOUT          (GPIOOUT),
    .GPIOEN           (GPIOEN),
    .UARTSin          (UARTSin),
    .UARTSout         (UARTSout),
    .SPIIn            (SPIIn),
    .SPIOut           (SPIOut),
    .SPICS            (SPICS),
    .SPICLK           (SPICLK),
    .SDCIn            (SDCIn),
    .SDCCmd           (SDCCmd),
    .SDCCS            (SDCCS),
    .SDCCLK           (SDCCLK),

    // Debugger Subsystem Pins
    .dbg_sel          (dbg_sel),
    .uart_rx          (uart_rx),
    .uart_tx          (uart_tx),
    .ft1248_clk       (ft1248_clk),
    .ft1248_ss_n      (ft1248_ss_n),
    .ft1248_miso      (ft1248_miso),
    .ft1248_miosio    (ft1248_miosio),
    .core_halted_led  (led_core_halted)
  );

endmodule
