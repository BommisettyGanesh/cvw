module tsetlin_ahb_wrapper #(
  parameter XLEN = 32
) (
  input  logic            clk,
  input  logic            reset,
  input  logic            HSEL,
  input  logic [XLEN-1:0] HADDR,
  input  logic [XLEN-1:0] HWDATA,
  input  logic            HWRITE,
  input  logic [2:0]      HSIZE,
  input  logic [2:0]      HBURST,
  input  logic [3:0]      HPROT,
  input  logic [1:0]      HTRANS,
  input  logic            HREADY,
  output logic            HREADYOUT,
  output logic            HRESP,
  output logic [XLEN-1:0] HRDATA
);

  logic write_en, read_en;
  logic [XLEN-1:0] addr_reg;
  logic valid_trans;

  assign valid_trans = HSEL && HREADY && (HTRANS == 2'b10 || HTRANS == 2'b11); // NONSEQ or SEQ

  always_ff @(posedge clk) begin
    if (reset) begin
      write_en <= 0;
      read_en <= 0;
      addr_reg <= '0;
    end else begin
      write_en <= valid_trans && HWRITE;
      read_en <= valid_trans && !HWRITE;
      if (valid_trans) addr_reg <= HADDR;
    end
  end

  // Dummy registers to simulate Tsetlin Machine
  logic [31:0] config_reg;

  always_ff @(posedge clk) begin
    if (reset) begin
        config_reg <= '0;
    end else if (write_en && addr_reg[7:0] == 8'h00) begin
        config_reg <= HWDATA;
    end
  end

  always_comb begin
    HREADYOUT = 1'b1; // Always ready (no wait states in this mock)
    HRESP = 1'b0;     // OKAY response
    HRDATA = '0;

    if (read_en) begin
      if (addr_reg[7:0] == 8'h00) begin
          HRDATA = config_reg;
      end else if (addr_reg[7:0] == 8'h04) begin
          HRDATA = 32'hCAFEBABE; // Return magic status indicating accelerator is alive
      end
    end
  end

endmodule
