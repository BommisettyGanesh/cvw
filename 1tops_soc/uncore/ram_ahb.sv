// ram_ahb.sv
// Purpose: On-chip RAM, external to core, with AHB interface

module ram_ahb #(
  parameter XLEN        = 32,
  parameter PA_BITS     = 32,
  parameter RANGE       = 65535,
  parameter BASE_ADDR   = 32'h8000_0000,
  parameter PRELOAD     = 0,
  parameter string MEMFILE = "test.mem",
  parameter RAM_LATENCY = 0
)(
  input  logic                 HCLK,
  input  logic                 HRESETn,
  input  logic                 HSELRam,
  input  logic [PA_BITS-1:0]   HADDR,
  input  logic                 HWRITE,
  input  logic                 HREADY,
  input  logic [1:0]           HTRANS,
  input  logic [XLEN-1:0]      HWDATA,
  input  logic [XLEN/8-1:0]    HWSTRB,
  output logic [XLEN-1:0]      HREADRam,
  output logic                 HRESPRam,
  output logic                 HREADYRam
);

  localparam WORDS      = (RANGE + 1) / (XLEN / 8);
  localparam ADDR_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;
  localparam OFFSET     = $clog2(XLEN / 8);

  logic [PA_BITS-1:0]   HADDRD, RamAddr;
  logic                 initTrans;
  logic                 memwrite, memwriteD, memread;
  logic                 nextHREADYRam;
  logic                 DelayReady;

  // AHB transaction detection
  assign initTrans = HREADY & HSELRam & HTRANS[1];
  assign memwrite  = initTrans & HWRITE;
  assign memread   = initTrans & ~HWRITE;

  // Pipeline register for address and write control
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      memwriteD <= 1'b0;
      HADDRD    <= '0;
    end else if (HREADY) begin
      memwriteD <= memwrite;
      HADDRD    <= HADDR;
    end
  end

  // Stall on read immediately following write (single port conflict avoidance)
  assign nextHREADYRam = (~(memwriteD & memread)) & ~DelayReady;

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) HREADYRam <= 1'b1;
    else          HREADYRam <= nextHREADYRam;
  end

  assign HRESPRam = 1'b0; // OKAY

  // Address selection: use delayed address during write data phase or stall
  assign RamAddr = (memwriteD | ~HREADY) ? HADDRD : HADDR;
  wire [PA_BITS-1:0]    rel_addr  = RamAddr - BASE_ADDR;
  wire [ADDR_WIDTH-1:0] word_addr = rel_addr[ADDR_WIDTH+OFFSET-1:OFFSET];

  // Backward-compatible alias signals for testbench hierarchical monitoring
  wire                  write_reg   = memwriteD;
  wire [ADDR_WIDTH-1:0] wr_addr_reg = word_addr;

`ifdef ALTERA_RESERVED_QIS
    `define INFER_BYTE_RAM_M9K
`elsif SYNTHESIS
    `define INFER_BYTE_RAM_M9K
`endif

`ifdef INFER_BYTE_RAM_M9K
  // 4 independent 8-bit RAM arrays: Guarantees 100% native M9K Block RAM inference
  // in Intel Quartus Prime without consuming hundreds of thousands of Logic Elements.
  (* ramstyle = "M9K" *) logic [7:0] mem0 [0:WORDS-1];
  (* ramstyle = "M9K" *) logic [7:0] mem1 [0:WORDS-1];
  (* ramstyle = "M9K" *) logic [7:0] mem2 [0:WORDS-1];
  (* ramstyle = "M9K" *) logic [7:0] mem3 [0:WORDS-1];

  always_ff @(posedge HCLK) begin
    if (memwriteD && HWSTRB[0]) mem0[word_addr] <= HWDATA[ 7: 0];
    if (memwriteD && HWSTRB[1]) mem1[word_addr] <= HWDATA[15: 8];
    if (memwriteD && HWSTRB[2]) mem2[word_addr] <= HWDATA[23:16];
    if (memwriteD && HWSTRB[3]) mem3[word_addr] <= HWDATA[31:24];
  end

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      HREADRam <= '0;
    end else begin
      HREADRam <= {mem3[word_addr], mem2[word_addr], mem1[word_addr], mem0[word_addr]};
    end
  end

`else
  // 32-bit memory array with byte enables (directly accessible by testbench preloads)
  logic [XLEN-1:0] mem [0:WORDS-1];

  initial begin
    if (PRELOAD && MEMFILE != "") begin
      $readmemh(MEMFILE, mem);
    end
  end

  // Byte-lane masked synchronous write (always allows testbench backdoor initialization)
  integer b;
  always @(posedge HCLK) begin
    if (memwriteD) begin
      for (b = 0; b < XLEN/8; b = b + 1) begin
        if (HWSTRB[b]) begin
          mem[word_addr][b*8 +: 8] <= HWDATA[b*8 +: 8];
        end
      end
    end
  end

  // Synchronous read
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      HREADRam <= '0;
    end else begin
      HREADRam <= mem[word_addr];
    end
  end
`endif

  // Optional wait-state / latency testing
  generate
    if (RAM_LATENCY > 0) begin : gen_latency
      logic [7:0] Cycle;
      logic       CntEn, CntRst;
      logic       CycleFlag;

      typedef enum logic {READY_ST, DELAY_ST} statetype;
      statetype CurrState, NextState;

      always_ff @(posedge HCLK or negedge HRESETn) begin
        if (~HRESETn) CurrState <= READY_ST;
        else          CurrState <= NextState;
      end

      always_comb begin
        case (CurrState)
          READY_ST: if (initTrans & ~CycleFlag) NextState = DELAY_ST;
                    else                        NextState = READY_ST;
          DELAY_ST: if (CycleFlag)              NextState = READY_ST;
                    else                        NextState = DELAY_ST;
          default:                              NextState = READY_ST;
        endcase
      end

      always_ff @(posedge HCLK or negedge HRESETn) begin
        if (~HRESETn || CntRst) Cycle <= 8'd0;
        else if (CntEn)         Cycle <= Cycle + 8'd1;
      end

      assign CycleFlag  = (Cycle == RAM_LATENCY[7:0]);
      assign CntEn      = (NextState == DELAY_ST);
      assign DelayReady = (NextState == DELAY_ST);
      assign CntRst     = (NextState == READY_ST);
    end else begin : gen_no_latency
      assign DelayReady = 1'b0;
    end
  endgenerate

endmodule
