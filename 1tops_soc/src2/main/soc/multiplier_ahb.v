// =============================================================================
// Module: multiplier_ahb
// Purpose: AMBA 3 AHB-Lite Hardware Accelerator Slave
// Reference: cvw/1tops_soc/src/accelerator/multiplier_ahb.sv (David_Harris@hmc.edu)
// Address Space: 0x3000_0000 - 0x30FF_FFFF (EXT_MEM space in Wally SoC)
// Register Map:
//   - 0x00: Operand A (32-bit R/W)
//   - 0x04: Operand B (32-bit R/W)
//   - 0x08: Product Output (32-bit Read-Only: Operand A * Operand B)
//   - 0x0C: Debug Character Output (Write-Only, testbench console print)
// =============================================================================

module multiplier_ahb #(
    parameter XLEN = 32
)(
    input                  clk,
    input                  reset,
    input                  HSEL,
    input      [XLEN-1:0]  HADDR,
    input      [XLEN-1:0]  HWDATA,
    input                  HWRITE,
    input      [ 2:0]      HSIZE,
    input      [ 2:0]      HBURST,
    input      [ 3:0]      HPROT,
    input      [ 1:0]      HTRANS,
    input                  HREADY,
    output                 HREADYOUT,
    output                 HRESP,
    output reg [XLEN-1:0]  HRDATA
);

    reg write_en;
    reg read_en;
    reg [XLEN-1:0] addr_reg;
    wire valid_trans = HSEL && HREADY && (HTRANS == 2'b10 || HTRANS == 2'b11);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_en <= 1'b0;
            read_en  <= 1'b0;
            addr_reg <= {XLEN{1'b0}};
        end else begin
            write_en <= valid_trans && HWRITE;
            read_en  <= valid_trans && !HWRITE;
            if (valid_trans)
                addr_reg <= HADDR;
        end
    end

    // Registers for multiplier operands
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    wire [31:0] product = operand_a * operand_b;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            operand_a <= 32'd0;
            operand_b <= 32'd0;
        end else if (write_en) begin
            if (addr_reg[7:0] == 8'h00)
                operand_a <= HWDATA;
            else if (addr_reg[7:0] == 8'h04)
                operand_b <= HWDATA;
`ifndef SYNTHESIS
            // synthesis translate_off
            else if (addr_reg[7:0] == 8'h0C) begin
                if (HWDATA[7:0] == 8'h0A)
                    $display("");
                else
                    $write("%c", HWDATA[7:0]);
            end
            // synthesis translate_on
`endif
        end
    end

    assign HREADYOUT = 1'b1; // Single-cycle combinational multiply response
    assign HRESP     = 1'b0; // OKAY response

    always @(*) begin
        HRDATA = 32'd0;
        if (read_en) begin
            case (addr_reg[7:0])
                8'h00:   HRDATA = operand_a;
                8'h04:   HRDATA = operand_b;
                8'h08:   HRDATA = product;
                default: HRDATA = 32'd0;
            endcase
        end
    end

endmodule
