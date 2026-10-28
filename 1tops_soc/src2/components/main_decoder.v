// =============================================================================
// Module: main_decoder
// Purpose: Primary Opcode Decoder for RISC-V RV32I + Zicsr + Privileged
// Reference: CORE-V-WALLY (1tops_soc) src/ieu/controller.sv
// =============================================================================

module main_decoder (
    input  [6:0] op,
    input  [2:0] funct3,
    output [2:0] ResultSrc, // 3'b000: ALU, 3'b001: Mem, 3'b010: PC+4, 3'b011: LUI/AUIPC, 3'b100: CSR
    output       MemWrite, Branch, ALUSrc,
    output       RegWrite, Jump, Jalr,
    output [1:0] ImmSrc,
    output [1:0] ALUOp,
    output       CSRRead    // Active on valid CSR access
);

    // SYSTEM instructions with funct3 == 000 are privileged (mret, wfi, ecall, ebreak)
    wire is_priv = (op == 7'b1110011) && (funct3 == 3'b000);
    wire is_csr  = (op == 7'b1110011) && (funct3 != 3'b000) && (funct3 != 3'b100);

    reg [13:0] controls;

    always @(*) begin
        casez (op)
            // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_ALUOp_Jump_Jalr_Branch_CSRRead
            7'b0000011: controls = 14'b1_00_1_0_001_00_0_0_0_0; // lw
            7'b0100011: controls = 14'b0_01_1_1_000_00_0_0_0_0; // sw
            7'b0110011: controls = 14'b1_xx_0_0_000_10_0_0_0_0; // R-type
            7'b1100011: controls = 14'b0_10_0_0_000_01_0_0_1_0; // Branch
            7'b0010011: controls = 14'b1_00_1_0_000_10_0_0_0_0; // I-type ALU
            7'b1101111: controls = 14'b1_11_0_0_010_00_1_0_0_0; // jal
            7'b1100111: controls = 14'b1_00_1_0_010_00_0_1_0_0; // jalr
            7'b0?10111: controls = 14'b1_xx_x_0_011_xx_0_0_0_0; // lui or auipc
            7'b1110011: begin
                if (is_priv)
                    controls = 14'b0_00_0_0_000_00_0_0_0_0; // Privileged (mret, wfi, ecall, ebreak)
                else if (is_csr)
                    controls = 14'b1_xx_x_0_100_00_0_0_0_1; // SYSTEM (Zicsr)
                else
                    controls = 14'b0_00_0_0_000_00_0_0_0_0; // Reserved/Illegal SYSTEM
            end
            7'b0001111: controls = 14'b0_00_0_0_000_00_0_0_0_0; // FENCE / FENCE.I
            default:    controls = 14'b0_00_0_0_000_00_0_0_0_0;
        endcase
    end

    assign {RegWrite, ImmSrc, ALUSrc, MemWrite, ResultSrc, ALUOp, Jump, Jalr, Branch, CSRRead} = controls;

endmodule
