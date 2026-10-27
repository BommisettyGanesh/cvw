// rom_ahb.sv
// Purpose: On-chip ROM, external to core, with AHB interface

module rom_ahb #(
  parameter XLEN        = 32,
  parameter PA_BITS     = 32,
  parameter RANGE       = 65535,
  parameter PRELOAD     = 0,
  parameter string MEMFILE = ""
)(
  input  logic                 HCLK,
  input  logic                 HRESETn,
  input  logic                 HSELRom,
  input  logic [PA_BITS-1:0]   HADDR,
  input  logic                 HREADY,
  input  logic [1:0]           HTRANS,
  output logic [XLEN-1:0]      HREADRom,
  output logic                 HRESPRom,
  output logic                 HREADYRom
);

  localparam WORDS      = (RANGE + 1) / (XLEN / 8);
  localparam ADDR_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;
  localparam OFFSET     = $clog2(XLEN / 8);

  // Never stalls, returns OKAY
  assign HREADYRom = 1'b1;
  assign HRESPRom  = 1'b0;

  logic [XLEN-1:0] mem [0:WORDS-1];

// synthesis translate_off
  initial begin
    if (PRELOAD && MEMFILE != "") begin
      $readmemh(MEMFILE, mem);
    end
  end
// synthesis translate_on

  wire [ADDR_WIDTH-1:0] word_addr = HADDR[ADDR_WIDTH+OFFSET-1:OFFSET];

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      HREADRom <= '0;
    end else if (HSELRom & HREADY & HTRANS[1]) begin
      HREADRom <= mem[word_addr];
    end
  end

endmodule
