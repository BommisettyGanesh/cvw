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

module wallypipelinedsoc import cvw::*; #(parameter cvw_t P)  (
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
  output logic                SDCCLK            // SDC Clock       from   SPI Clock
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

//
//
  // Debugger to Uncore UART connection signals
  logic [7:0]          dbg_uart_tx_data;
  logic                dbg_uart_tx_valid;
  logic                dbg_uart_tx_ready;
  logic [7:0]          dbg_uart_rx_data;
  logic                dbg_uart_rx_valid;
  logic                dbg_uart_rx_ready;

  // Debugger AHB Master signals
  logic                dbg_core_halt;
  logic                dbg_core_reset;
  logic [31:0]         dbg_haddr;
  logic [ 2:0]         dbg_hburst;
  logic                dbg_hmastlock;
  logic [ 3:0]         dbg_hprot;
  logic [ 2:0]         dbg_hsize;
  logic [ 1:0]         dbg_htrans;
  logic [31:0]         dbg_hwdata;
  logic                dbg_hwrite;
  logic [31:0]         dbg_hrdata;
  logic                dbg_hready;
  logic                dbg_hresp;

  // Core AHB Master signals before bus arbiter
  logic [P.PA_BITS-1:0] core_haddr;
  logic [P.AHBW-1:0]    core_hwdata;
  logic [P.XLEN/8-1:0]  core_hwstrb;
  logic                 core_hwrite;
  logic [2:0]           core_hsize;
  logic [2:0]           core_hburst;
  logic [3:0]           core_hprot;
  logic [1:0]           core_htrans;
  logic                 core_hmastlock;
  logic                 core_hready;
  logic                 core_hresp;
  logic [P.AHBW-1:0]    core_hrdata;
//
//

  // synchronize reset to SOC clock domain
  synchronizer resetsync(.clk, .d(reset_ext), .q(reset));

  // instantiate processor and internal memories
  wallypipelinedcore #(P) core(.clk, .reset,
    .MTimerInt, .MExtInt, .SExtInt, .MSwInt, .MTIME_CLINT,
//
//
    .HRDATA(core_hrdata), .HREADY(core_hready), .HRESP(core_hresp), .HCLK, .HRESETn,
    .HADDR(core_haddr), .HWDATA(core_hwdata), .HWSTRB(core_hwstrb),
    .HWRITE(core_hwrite), .HSIZE(core_hsize), .HBURST(core_hburst), .HPROT(core_hprot),
    .HTRANS(core_htrans), .HMASTLOCK(core_hmastlock), .ExternalStall(ExternalStall | dbg_core_halt)
//
//
   );

  // instantiate uncore if a bus interface exists
  if (P.BUS_SUPPORTED) begin : uncoregen // Hack to work around Verilator bug https://github.com/verilator/verilator/issues/4769
    uncore #(P) uncore(.HCLK, .HRESETn, .TIMECLK,
      .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .HRDATAEXT,
      .HREADYEXT, .HRESPEXT, .HRDATA, .HREADY, .HRESP, .HSELEXT,
      .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .GPIOIN, .GPIOOUT, .GPIOEN, .UARTSin,
      .UARTSout, .MTIME_CLINT, .SPIIn, .SPIOut, .SPICS, .SPICLK, .SDCIn, .SDCCmd, .SDCCS, .SDCCLK,
//
//
      .dbg_uart_tx_data, .dbg_uart_tx_valid, .dbg_uart_tx_ready,
      .dbg_uart_rx_data, .dbg_uart_rx_valid, .dbg_uart_rx_ready
//
//
    );
  end else begin
    assign {HRDATA, HREADY, HRESP, HSELEXT, MTimerInt, MSwInt, MExtInt, SExtInt,
            MTIME_CLINT, GPIOOUT, GPIOEN, UARTSout, SPIOut, SPICS, SPICLK, SDCCmd, SDCCS, SDCCLK} = '0;
//
//
    assign {dbg_uart_rx_valid, dbg_uart_tx_ready} = '0;
    assign dbg_uart_rx_data = '0;
//
//
  end

//
//
  assign HWSTRB = (dbg_core_halt) ? {P.XLEN/8{1'b1}} : core_hwstrb;

  // Instantiate Redesigned Debugger Subsystem (transferring data to/from uncore UART)
  riscv_debugger_top #(
    .PROMPT_CHAR("]")
  ) u_debugger (
    .clk             (clk),
    .rst_n           (reset),
    .uart_rx_data    (dbg_uart_rx_data),
    .uart_rx_valid   (dbg_uart_rx_valid),
    .uart_rx_ready   (dbg_uart_rx_ready),
    .uart_tx_data    (dbg_uart_tx_data),
    .uart_tx_valid   (dbg_uart_tx_valid),
    .uart_tx_ready   (dbg_uart_tx_ready),
    .core_halt_o     (dbg_core_halt),
    .core_reset_o    (dbg_core_reset),
    .core_halted_i   (dbg_core_halt),
    .DEBUG_HADDR     (dbg_haddr),
    .DEBUG_HBURST    (dbg_hburst),
    .DEBUG_HMASTLOCK (dbg_hmastlock),
    .DEBUG_HPROT     (dbg_hprot),
    .DEBUG_HSIZE     (dbg_hsize),
    .DEBUG_HTRANS    (dbg_htrans),
    .DEBUG_HWDATA    (dbg_hwdata),
    .DEBUG_HWRITE    (dbg_hwrite),
    .DEBUG_HRDATA    (dbg_hrdata),
    .DEBUG_HREADY    (dbg_hready),
    .DEBUG_HRESP     (dbg_hresp),
    .GPO8            (),
    .GPI8            (8'h00)
  );

  // Instantiate 2-to-1 AHB Bus Arbiter / Mux
  ahb_mux #(
    .ADDR_WIDTH (P.PA_BITS),
    .DATA_WIDTH (P.AHBW)
  ) u_ahb_mux (
    .HCLK         (clk),
    .HRESETn      (reset),
    .core_halt    (dbg_core_halt),

    // M0: CPU Core
    .M0_HADDR     (core_haddr),
    .M0_HWDATA    (core_hwdata),
    .M0_HWRITE    (core_hwrite),
    .M0_HTRANS    (core_htrans),
    .M0_HSIZE     (core_hsize),
    .M0_HBURST    (core_hburst),
    .M0_HPROT     (core_hprot),
    .M0_HMASTLOCK (core_hmastlock),
    .M0_HRDATA    (core_hrdata),
    .M0_HREADY    (core_hready),
    .M0_HRESP     (core_hresp),

    // M1: Debugger
    .M1_HADDR     (dbg_haddr),
    .M1_HWDATA    (dbg_hwdata),
    .M1_HWRITE    (dbg_hwrite),
    .M1_HTRANS    (dbg_htrans),
    .M1_HSIZE     (dbg_hsize),
    .M1_HBURST    (dbg_hburst),
    .M1_HPROT     (dbg_hprot),
    .M1_HMASTLOCK (dbg_hmastlock),
    .M1_HRDATA    (dbg_hrdata),
    .M1_HREADY    (dbg_hready),
    .M1_HRESP     (dbg_hresp),

    // Downstream Slave Bus
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
//
//

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
