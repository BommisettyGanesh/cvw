module multiplier_ahb #(
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

  // Registers for multiplier operands
  logic [31:0] operand_a;
  logic [31:0] operand_b;
  logic [31:0] product;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      operand_a <= 0;
      operand_b <= 0;
    end else if (write_en) begin
      if (addr_reg[7:0] == 8'h00)
        operand_a <= HWDATA;
      else if (addr_reg[7:0] == 8'h04)
        operand_b <= HWDATA;
      else if (addr_reg[7:0] == 8'h0C) begin
        if (HWDATA[7:0] == 8'h0A) begin
            $display(""); // Print newline and flush
        end else begin
            $write("%c", HWDATA[7:0]);
        end
      end
    end
  end

  // Simple combinational multiplication
  assign product = operand_a * operand_b;

  always_comb begin
    HREADYOUT = 1'b1; // Always ready (1-cycle combinational multiply)
    HRESP = 1'b0;     // OKAY response
    HRDATA = '0;

    if (read_en) begin
      if (addr_reg[7:0] == 8'h00) HRDATA = operand_a;
      else if (addr_reg[7:0] == 8'h04) HRDATA = operand_b;
      else if (addr_reg[7:0] == 8'h08) HRDATA = product;
    end
  end

endmodule
