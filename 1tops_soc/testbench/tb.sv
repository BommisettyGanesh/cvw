module tb;
  logic clk;
  logic reset;

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
  wallypipelinedsoc #(
    .ASIC(0)
  ) soc (
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

  // Convolutional Tsetlin Machine Accelerator Wrapper
  tsetlin_ahb_wrapper #(
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

  // Clock Generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Dump logic for Verilator
  initial begin
    $dumpfile("trace.vcd");
    $dumpvars(0, tb);
  end

endmodule
