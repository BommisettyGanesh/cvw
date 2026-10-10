///////////////////////////////////////////
// wally-pipelinedsoc.sv
//
// Written: David_Harris@hmc.edu 6 November 2020
// Modified:
//
// Purpose: System on chip including pipelined processor and uncore memories/peripherals
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

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
  output logic                reset,            // reset synchronized to clk to prevent races on release
  // AHB Interface (External Memory space designated for Convolutional Tsetlin Machine Accelerator)
  // (These signals are now internal, connected to the instantiated accelerator)
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
  input  logic                SDCIn,            // SDC DATA[0]     to     SPI DI
  output logic                SDCCmd,           // SDC CMD         from   SPI DO
  output logic [3:0]          SDCCS,            // SDC Card Detect from   SPI CS
  output logic                SDCCLK,           // SDC Clock       from   SPI Clock

  // Dual-Protocol Debugger Hardware Pins (Direct FPGA Connections)
  input  logic                dbg_sel         = 1'b0, // 0 = Dedicated UART, 1 = Dedicated FT1248
  input  logic                uart_rx         = 1'b1, // PMOD JA Pin 1 (from host PC, idle HIGH)
  output logic                uart_tx,                // PMOD JA Pin 2 (to host PC)
  output logic                ft1248_clk,             // PMOD JB Pin 1 (SCLK to FT232H)
  output logic                ft1248_ss_n,            // PMOD JB Pin 2 (SS# to FT232H)
  input  logic                ft1248_miso     = 1'b1, // PMOD JB Pin 3 (MISO / RXF# idle HIGH)
  inout  wire [FT_WIDTH-1:0]  ft1248_miosio,          // PMOD JB Pin 4 (MIOSIO Bidirectional Data)
  output logic                core_halted_led         // LED output indicating core is halted
);

  // Uncore signals
  logic [P.AHBW-1:0]          HRDATA;           // from AHB mux in uncore
  logic                       HRESP;            // response from AHB
  logic                       MTimerInt, MSwInt;// timer and software interrupts from CLINT
  logic [63:0]                MTIME_CLINT;      // from CLINT to CSRs
  logic                       MExtInt,SExtInt;  // from PLIC

  // Internal AHB signals for the embedded accelerator
  logic [P.AHBW-1:0]          HRDATAEXT;
  logic                       HREADYEXT, HRESPEXT, HSELEXT;

  // synchronize reset to SOC clock domain
  synchronizer resetsync(.clk, .d(reset_ext), .q(reset));

  // Internal CPU Core AHB Master signals
  logic [P.PA_BITS-1:0]       core_HADDR;
  logic [P.AHBW-1:0]          core_HWDATA;
  logic [P.XLEN/8-1:0]        core_HWSTRB;
  logic                       core_HWRITE;
  logic [2:0]                 core_HSIZE;
  logic [2:0]                 core_HBURST;
  logic [3:0]                 core_HPROT;
  logic [1:0]                 core_HTRANS;
  logic                       core_HMASTLOCK;
  logic [P.AHBW-1:0]          core_HRDATA;
  logic                       core_HREADY;
  logic                       core_HRESP;

  // Internal Debugger AHB Master signals
  logic [31:0]                dbg_HADDR;
  logic [31:0]                dbg_HWDATA;
  logic [1:0]                 dbg_HTRANS;
  logic [2:0]                 dbg_HSIZE;
  logic [2:0]                 dbg_HBURST;
  logic [3:0]                 dbg_HPROT;
  logic                       dbg_HWRITE;
  logic                       dbg_HMASTLOCK;
  logic [31:0]                dbg_HRDATA;
  logic                       dbg_HREADY;
  logic                       dbg_HRESP;
  logic                       dbg_core_halt;
  logic                       dbg_core_reset;

  // Zero-extend debugger address/data to match physical bus width (P.PA_BITS & P.AHBW)
  logic [P.PA_BITS-1:0]       dbg_HADDR_ext;
  logic [P.AHBW-1:0]          dbg_HWDATA_ext;

  if (P.PA_BITS >= 32)
    assign dbg_HADDR_ext = { {(P.PA_BITS-32){1'b0}}, dbg_HADDR };
  else
    assign dbg_HADDR_ext = dbg_HADDR[P.PA_BITS-1:0];

  if (P.AHBW >= 32)
    assign dbg_HWDATA_ext = { {(P.AHBW-32){1'b0}}, dbg_HWDATA };
  else
    assign dbg_HWDATA_ext = dbg_HWDATA[P.AHBW-1:0];

  // 1. Dual-Protocol Hardware Debugger Subsystem (UART + FT1248)
  riscv_debugger_top #(
    .CLK_FREQ    (CLK_FREQ),
    .BAUD_RATE   (BAUD_RATE),
    .PROMPT_CHAR (PROMPT_CHAR),
    .FT_WIDTH    (FT_WIDTH),
    .FT_CLKDIV   (FT_CLKDIV)
  ) u_debugger (
    .clk             (clk),
    .rst_n           (~reset),
    .dbg_sel         (dbg_sel),
    .uart_rx         (uart_rx),
    .uart_tx         (uart_tx),
    .ft1248_clk      (ft1248_clk),
    .ft1248_ss_n     (ft1248_ss_n),
    .ft1248_miso     (ft1248_miso),
    .ft1248_miosio   (ft1248_miosio),
    .core_halt_o     (dbg_core_halt),
    .core_reset_o    (dbg_core_reset),
    .core_halted_i   (dbg_core_halt),
    .DEBUG_HADDR     (dbg_HADDR),
    .DEBUG_HBURST    (dbg_HBURST),
    .DEBUG_HMASTLOCK (dbg_HMASTLOCK),
    .DEBUG_HPROT     (dbg_HPROT),
    .DEBUG_HSIZE     (dbg_HSIZE),
    .DEBUG_HTRANS    (dbg_HTRANS),
    .DEBUG_HWDATA    (dbg_HWDATA),
    .DEBUG_HWRITE    (dbg_HWRITE),
    .DEBUG_HRDATA    (dbg_HRDATA),
    .DEBUG_HREADY    (dbg_HREADY),
    .DEBUG_HRESP     (dbg_HRESP),
    .GPO8            (),
    .GPI8            ({7'b0, dbg_core_halt})
  );

  assign core_halted_led = dbg_core_halt;

  // 2. Instantiate CPU Core
  wallypipelinedcore #(P) core(
    .clk,
    .reset         (reset | dbg_core_reset),
    .MTimerInt, .MExtInt, .SExtInt, .MSwInt, .MTIME_CLINT,
    .HRDATA        (core_HRDATA),
    .HREADY        (core_HREADY),
    .HRESP         (core_HRESP),
    .HCLK,
    .HRESETn,
    .HADDR         (core_HADDR),
    .HWDATA        (core_HWDATA),
    .HWSTRB        (core_HWSTRB),
    .HWRITE        (core_HWRITE),
    .HSIZE         (core_HSIZE),
    .HBURST        (core_HBURST),
    .HPROT         (core_HPROT),
    .HTRANS        (core_HTRANS),
    .HMASTLOCK     (core_HMASTLOCK),
    .ExternalStall (ExternalStall | dbg_core_halt)
  );

  // 3. 2-to-1 AHB-Lite Bus Arbiter / Multiplexer
  ahb_mux #(
    .ADDR_WIDTH (P.PA_BITS),
    .DATA_WIDTH (P.AHBW)
  ) u_ahb_mux (
    .HCLK         (clk),
    .HRESETn      (~reset),
    .core_halt    (dbg_core_halt),

    // Master 0: CPU Core
    .M0_HADDR     (core_HADDR),
    .M0_HWDATA    (core_HWDATA),
    .M0_HWRITE    (core_HWRITE),
    .M0_HTRANS    (core_HTRANS),
    .M0_HSIZE     (core_HSIZE),
    .M0_HBURST    (core_HBURST),
    .M0_HPROT     (core_HPROT),
    .M0_HMASTLOCK (core_HMASTLOCK),
    .M0_HRDATA    (core_HRDATA),
    .M0_HREADY    (core_HREADY),
    .M0_HRESP     (core_HRESP),

    // Master 1: Debugger Subsystem
    .M1_HADDR     (dbg_HADDR_ext),
    .M1_HWDATA    (dbg_HWDATA_ext),
    .M1_HWRITE    (dbg_HWRITE),
    .M1_HTRANS    (dbg_HTRANS),
    .M1_HSIZE     (dbg_HSIZE),
    .M1_HBURST    (dbg_HBURST),
    .M1_HPROT     (dbg_HPROT),
    .M1_HMASTLOCK (dbg_HMASTLOCK),
    .M1_HRDATA    (dbg_HRDATA),
    .M1_HREADY    (dbg_HREADY),
    .M1_HRESP     (dbg_HRESP),

    // Shared Downstream AHB Bus to Uncore & Peripherals
    .S_HADDR      (HADDR),
    .S_HWDATA     (HWDATA),
    .S_HWRITE     (HWRITE),
    .S_HTRANS     (HTRANS),
    .S_HSIZE      (HSIZE),
    .S_HBURST     (HBURST),
    .S_HPROT      (HPROT),
    .S_HMASTLOCK  (HMASTLOCK),
    .S_HRDATA     (HRDATA),
    .S_HREADY     (HREADY),
    .S_HRESP      (HRESP)
  );

  assign HWSTRB = (dbg_core_halt) ? { (P.XLEN/8){1'b1} } : core_HWSTRB;

  // instantiate uncore if a bus interface exists
  if (P.BUS_SUPPORTED) begin : uncoregen // Hack to work around Verilator bug https://github.com/verilator/verilator/issues/4769
    uncore #(P) uncore(.HCLK, .HRESETn, .TIMECLK,
      .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .HRDATAEXT,
      .HREADYEXT, .HRESPEXT, .HRDATA, .HREADY, .HRESP, .HSELEXT,
      .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .GPIOIN, .GPIOOUT, .GPIOEN, .UARTSin,
      .UARTSout, .MTIME_CLINT, .SPIIn, .SPIOut, .SPICS, .SPICLK, .SDCIn, .SDCCmd, .SDCCS, .SDCCLK);
  end else begin
    assign {HRDATA, HREADY, HRESP, HSELEXT, MTimerInt, MSwInt, MExtInt, SExtInt,
            MTIME_CLINT, GPIOOUT, GPIOEN, UARTSout, SPIOut, SPICS, SPICLK, SDCCmd, SDCCS, SDCCLK} = '0;
  end

  // Multiplier AHB Slave (Placeholder for Tsetlin Machine Accelerator)
  multiplier_ahb #(
    .XLEN(32)
  ) accel (
    .clk(clk),
    .reset(reset),
    .HSEL(HSELEXT),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .HWRITE(HWRITE),
    .HSIZE(HSIZE),
    .HBURST(HBURST),
    .HPROT(HPROT),
    .HTRANS(HTRANS),
    .HREADY(HREADY),
    .HREADYOUT(HREADYEXT),
    .HRESP(HRESPEXT),
    .HRDATA(HRDATAEXT)
  );

endmodule
