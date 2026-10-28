// =============================================================================
// Module: controller
// Purpose: Pipelined Instruction Controller integrating Main Decoder,
//          ALU Decoder, Privileged Decoder, and Wally Write Suppression.
// =============================================================================

module controller (
    input  [31:0] InstrD,
    output [2:0]  ResultSrc,
    output        MemWrite,
    output        ALUSrc,
    output        RegWrite, Branch, Jump, Jalr,
    output [1:0]  ImmSrc,
    output [3:0]  ALUControl,
    output        CSRRead,
    output        CSRWrite,
    output        mretD,
    output        wfiD,
    output        ecallD,
    output        ebreakD,
    output        IllegalInstrD,
    output        FenceID
);

    wire [6:0] op       = InstrD[6:0];
    wire [2:0] funct3   = InstrD[14:12];
    wire       funct7b5 = InstrD[30];
    wire [4:0] rs1      = InstrD[19:15];

    assign FenceID      = (op == 7'b0001111) && (funct3 == 3'b001);

    wire [1:0] ALUOp;
    wire       CSRRead_int;
    wire       PrivilegedD, CSRInstrD, IllegalPrivD, IllegalCSRD;

    main_decoder md (
        .op(op),
        .funct3(funct3),
        .ResultSrc(ResultSrc),
        .MemWrite(MemWrite),
        .Branch(Branch),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .Jump(Jump),
        .Jalr(Jalr),
        .ImmSrc(ImmSrc),
        .ALUOp(ALUOp),
        .CSRRead(CSRRead_int)
    );

    alu_decoder ad (
        .opb5(op[5]),
        .funct3(funct3),
        .funct7b5(funct7b5),
        .ALUOp(ALUOp),
        .ALUControl(ALUControl)
    );

    priv_decoder pd (
        .InstrD(InstrD),
        .PrivilegedD(PrivilegedD),
        .CSRInstrD(CSRInstrD),
        .mretD(mretD),
        .wfiD(wfiD),
        .ecallD(ecallD),
        .ebreakD(ebreakD),
        .IllegalPrivD(IllegalPrivD),
        .IllegalCSRD(IllegalCSRD)
    );

    // Wally CSR Write Suppression:
    // If funct3[1] == 1 (CSRRS/CSRRC/CSRRSI/CSRRCI) and source operand is zero, suppress CSR write
    wire CSRZeroSrcD = (rs1 == 5'b00000);
    assign CSRRead   = CSRRead_int;
    assign CSRWrite  = CSRRead_int & !(CSRZeroSrcD & funct3[1]);

    // IllegalInstrD: Connected to priv_decoder illegal privileged and illegal CSR outputs.
    // Since these only assert on SYSTEM instructions (op == 7'b1110011), they never false-trigger.
    assign IllegalInstrD = IllegalPrivD | IllegalCSRD;

endmodule
