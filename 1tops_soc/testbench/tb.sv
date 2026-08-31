module tb(
  input logic clk,
  input logic reset
);
  import cvw::*;
  `include "config.vh"
  `include "parameter-defs.vh"

  // External AHB Interface
  logic [31:0] HRDATAEXT;
  logic        HREADYEXT;
  logic        HRESPEXT;
  logic        HSELEXT;
  logic [31:0] HADDREXT;
  logic [31:0] HWDATATAEXT;
  logic        HWRITEEXT;
  logic [2:0]  HSIZEEXT;
  logic [2:0]  HBURSTEXT;
  logic [3:0]  HPROTEXT;
  logic [1:0]  HTRANSEXT;
  logic        HMASTLOCKEXT;



  // SoC Instantiation
  wallypipelinedsoc #(P) soc (
    .clk(clk),
    .reset_ext(reset),
    .HRDATAEXT(HRDATAEXT),
    .HREADYEXT(HREADYEXT),
    .HRESPEXT(HRESPEXT),
    .HSELEXT(HSELEXT),
    .HADDR(HADDREXT),
    .HWDATA(HWDATATAEXT),
    .HWRITE(HWRITEEXT),
    .HSIZE(HSIZEEXT),
    .HBURST(HBURSTEXT),
    .HPROT(HPROTEXT),
    .HTRANS(HTRANSEXT),
    .HMASTLOCK(HMASTLOCKEXT),
    .ExternalStall(1'b0)
  );

  // Multiplier AHB Slave (Temporary stand-in for Tsetlin Machine)
  multiplier_ahb #(
    .XLEN(32)
  ) accel (
    .clk(clk),
    .reset(reset),
    .HSEL(HSELEXT),
    .HADDR(HADDREXT),
    .HWDATA(HWDATATAEXT),
    .HWRITE(HWRITEEXT),
    .HSIZE(HSIZEEXT),
    .HBURST(HBURSTEXT),
    .HPROT(HPROTEXT),
    .HTRANS(HTRANSEXT),
    .HREADY(1'b1),
    .HREADYOUT(HREADYEXT),
    .HRESP(HRESPEXT),
    .HRDATA(HRDATAEXT)
  );

endmodule
