//-----------------------------------------------------------------------------
// 2-Master AHB-Lite Bus Arbiter and Multiplexer
// Connects RISC-V CPU Core (Master 0) and SoCDebug (Master 1)
// to Downstream Memory & Peripherals (Uncore + Accelerator)
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module ahb_mux #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                  HCLK,
    input  wire                  HRESETn,

    // Priority hint: 1 = Core is halted, Debugger gets top priority
    input  wire                  core_halt,

    //-------------------------------------------------------------------------
    // Master 0: RISC-V CPU Core
    //-------------------------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0] M0_HADDR,
    input  wire [DATA_WIDTH-1:0] M0_HWDATA,
    input  wire                  M0_HWRITE,
    input  wire [1:0]            M0_HTRANS,
    input  wire [2:0]            M0_HSIZE,
    input  wire [2:0]            M0_HBURST,
    input  wire [3:0]            M0_HPROT,
    input  wire                  M0_HMASTLOCK,
    output wire [DATA_WIDTH-1:0] M0_HRDATA,
    output wire                  M0_HREADY,
    output wire                  M0_HRESP,

    //-------------------------------------------------------------------------
    // Master 1: Debugger Controller (SoCDebug AHB)
    //-------------------------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0] M1_HADDR,
    input  wire [DATA_WIDTH-1:0] M1_HWDATA,
    input  wire                  M1_HWRITE,
    input  wire [1:0]            M1_HTRANS,
    input  wire [2:0]            M1_HSIZE,
    input  wire [2:0]            M1_HBURST,
    input  wire [3:0]            M1_HPROT,
    input  wire                  M1_HMASTLOCK,
    output wire [DATA_WIDTH-1:0] M1_HRDATA,
    output wire                  M1_HREADY,
    output wire                  M1_HRESP,

    //-------------------------------------------------------------------------
    // Slave Interface: To Downstream System Interconnect / Uncore
    //-------------------------------------------------------------------------
    output wire [ADDR_WIDTH-1:0] S_HADDR,
    output wire [DATA_WIDTH-1:0] S_HWDATA,
    output wire                  S_HWRITE,
    output wire [1:0]            S_HTRANS,
    output wire [2:0]            S_HSIZE,
    output wire [2:0]            S_HBURST,
    output wire [3:0]            S_HPROT,
    output wire                  S_HMASTLOCK,
    input  wire [DATA_WIDTH-1:0] S_HRDATA,
    input  wire                  S_HREADY,
    input  wire                  S_HRESP
);

    // Master 0 (Core) transfer request (NONSEQ or SEQ)
    wire m0_req = (M0_HTRANS == 2'b10) || (M0_HTRANS == 2'b11);
    // Master 1 (Debugger) transfer request (NONSEQ or SEQ)
    wire m1_req = (M1_HTRANS == 2'b10) || (M1_HTRANS == 2'b11);

    // Pipelined grant state:
    // grant_addr: current master driving address phase
    // grant_data: current master in data phase
    reg grant_addr;
    reg grant_data;

    // Next address grant logic:
    // 0 = M0 (Core), 1 = M1 (Debugger)
    reg next_grant_addr;

    always @(*) begin
        if (core_halt) begin
            // When core is halted, Debugger has absolute priority
            if (m1_req)
                next_grant_addr = 1'b1;
            else if (m0_req)
                next_grant_addr = 1'b0;
            else
                next_grant_addr = grant_addr;
        end else begin
            // When core is running, Core has default priority
            // Debugger can take bus if Core is IDLE
            if (m0_req)
                next_grant_addr = 1'b0;
            else if (m1_req)
                next_grant_addr = 1'b1;
            else
                next_grant_addr = grant_addr;
        end
    end

    // Sequential update of grants
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            grant_addr <= 1'b0;
            grant_data <= 1'b0;
        end else if (S_HREADY) begin
            grant_addr <= next_grant_addr;
            grant_data <= grant_addr;
        end
    end

    //-------------------------------------------------------------------------
    // Address Phase Multiplexer (driven by grant_addr)
    //-------------------------------------------------------------------------
    assign S_HADDR     = (grant_addr == 1'b1) ? M1_HADDR     : M0_HADDR;
    assign S_HWRITE    = (grant_addr == 1'b1) ? M1_HWRITE    : M0_HWRITE;
    assign S_HTRANS    = (grant_addr == 1'b1) ? M1_HTRANS    : M0_HTRANS;
    assign S_HSIZE     = (grant_addr == 1'b1) ? M1_HSIZE     : M0_HSIZE;
    assign S_HBURST    = (grant_addr == 1'b1) ? M1_HBURST    : M0_HBURST;
    assign S_HPROT     = (grant_addr == 1'b1) ? M1_HPROT     : M0_HPROT;
    assign S_HMASTLOCK = (grant_addr == 1'b1) ? M1_HMASTLOCK : M0_HMASTLOCK;

    //-------------------------------------------------------------------------
    // Data Phase Multiplexer (driven by grant_data)
    //-------------------------------------------------------------------------
    assign S_HWDATA    = (grant_data == 1'b1) ? M1_HWDATA    : M0_HWDATA;

    // Response routing
    assign M0_HRDATA   = S_HRDATA;
    assign M1_HRDATA   = S_HRDATA;
    assign M0_HRESP    = (grant_data == 1'b0) ? S_HRESP : 1'b0;
    assign M1_HRESP    = (grant_data == 1'b1) ? S_HRESP : 1'b0;

    // HREADY gating:
    // Granted master receives slave HREADY.
    // Waiting master trying to transfer is held with HREADY=0 until granted.
    assign M0_HREADY   = (grant_addr == 1'b0 && grant_data == 1'b0) ? S_HREADY :
                         (m0_req ? 1'b0 : 1'b1);

    assign M1_HREADY   = (grant_addr == 1'b1 && grant_data == 1'b1) ? S_HREADY :
                         (m1_req ? 1'b0 : 1'b1);

endmodule
