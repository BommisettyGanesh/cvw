// =============================================================================
// Module: pl_reg_em
// Purpose: Pipeline Register E -> M with Stall and Flush for Traps & AHB Wait-States
// =============================================================================

module pl_reg_em (
    input             clk,
    input             reset,
    input             clr,          // Pipeline flush (traps, mret)
    input             StallM,       // AHB global pipeline stall enable
    input             RegWriteE, MemWriteE,
    input [2:0]       ResultSrcE,
    input [31:0]      ALUResultE, WriteDataE, PCPlus4E,
    input [4:0]       RdE,
    input [31:0]      PCE, lAuiPCE,
    input [2:0]       funct3E,
    input [31:0]      SrcAE,
    input [4:0]       uimmE,
    input [11:0]      CSRAdrE,
    input             CSRReadE, CSRWriteE,
    input             mretE, wfiE, ecallE, ebreakE, IllegalInstrE,
    input             ValidE,
    input [31:0]      InstrE,

    output reg        RegWriteM, MemWriteM,
    output reg [2:0]  ResultSrcM,
    output reg [31:0] ALUResultM, WriteDataM, PCPlus4M,
    output reg [4:0]  RdM,
    output reg [31:0] PCM, lAuiPCM,
    output reg [2:0]  funct3M,
    output reg [31:0] SrcAM,
    output reg [4:0]  uimmM,
    output reg [11:0] CSRAdrM,
    output reg        CSRReadM, CSRWriteM,
    output reg        mretM, wfiM, ecallM, ebreakM, IllegalInstrM,
    output reg        ValidM,
    output reg [31:0] InstrM
);

always @(posedge clk) begin
    if (reset || clr) begin
        RegWriteM     <= 0;
        MemWriteM     <= 0;
        ResultSrcM    <= 0;
        ALUResultM    <= 0;
        WriteDataM    <= 0;
        PCPlus4M      <= 0;
        RdM           <= 0;
        PCM           <= 0;
        lAuiPCM       <= 0;
        funct3M       <= 0;
        SrcAM         <= 0;
        uimmM         <= 0;
        CSRAdrM       <= 0;
        CSRReadM      <= 0;
        CSRWriteM     <= 0;
        mretM         <= 0;
        wfiM          <= 0;
        ecallM        <= 0;
        ebreakM       <= 0;
        IllegalInstrM <= 0;
        ValidM        <= 0;
        InstrM        <= 32'h00000013;
    end else if (!StallM) begin
        RegWriteM     <= RegWriteE;
        MemWriteM     <= MemWriteE;
        ResultSrcM    <= ResultSrcE;
        ALUResultM    <= ALUResultE;
        WriteDataM    <= WriteDataE;
        PCPlus4M      <= PCPlus4E;
        RdM           <= RdE;
        PCM           <= PCE;
        lAuiPCM       <= lAuiPCE;
        funct3M       <= funct3E;
        SrcAM         <= SrcAE;
        uimmM         <= uimmE;
        CSRAdrM       <= CSRAdrE;
        CSRReadM      <= CSRReadE;
        CSRWriteM     <= CSRWriteE;
        mretM         <= mretE;
        wfiM          <= wfiE;
        ecallM        <= ecallE;
        ebreakM       <= ebreakE;
        IllegalInstrM <= IllegalInstrE;
        ValidM        <= ValidE;
        InstrM        <= InstrE;
    end
end

endmodule
