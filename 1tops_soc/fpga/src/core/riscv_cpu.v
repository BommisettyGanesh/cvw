// =============================================================================
// Module: riscv_cpu
// Purpose: Pipelined RV32I Core with Standard AMBA 3 AHB-Lite Master Interface
// =============================================================================

module riscv_cpu #(parameter RESET_PC = 32'h0000_0000) (
    input             HCLK,
    input             HRESETn,

    // AMBA 3 AHB-Lite Master Interface
    output     [31:0] HADDR,
    output     [31:0] HWDATA,
    output     [ 3:0] HWSTRB,
    output            HWRITE,
    output     [ 2:0] HSIZE,
    output     [ 2:0] HBURST,
    output     [ 3:0] HPROT,
    output     [ 1:0] HTRANS,
    output            HMASTLOCK,
    input      [31:0] HRDATA,
    input             HREADY,
    input             HRESP,

    // Instruction & Execution Trace Outputs
    output     [31:0] PC,
    output     [31:0] PCW,
    output     [31:0] ALUResultW,
    output     [31:0] WriteDataW,
    output     [31:0] Result,

    // Hardware Interrupt Lines
    input             MTimerInt,
    input             MSwInt,
    input             MExtInt,
    input      [63:0] MTIME_CLINT,

    // External Stall from Debugger / Step Controller
    input             ExternalStall,

    // Instruction Retired 1-Cycle Pulse from Writeback Stage
    output            InstrRetired,

    // Trap Monitoring Output
    output            TrapM,
    output            mretM
);

wire        ALUSrc, RegWrite, MemWrite, Branch, Jump, Jalr;
wire [2:0]  ResultSrc;
wire [1:0]  ImmSrc;
wire [3:0]  ALUControl;
wire [31:0] InstrD;
wire        CSRRead, CSRWrite;
wire        mretD, wfiD, ecallD, ebreakD, IllegalInstrD;
wire        FenceID;

controller c (
    .InstrD(InstrD),
    .ResultSrc(ResultSrc),
    .MemWrite(MemWrite),
    .ALUSrc(ALUSrc),
    .RegWrite(RegWrite),
    .Branch(Branch),
    .Jump(Jump),
    .Jalr(Jalr),
    .ImmSrc(ImmSrc),
    .ALUControl(ALUControl),
    .CSRRead(CSRRead),
    .CSRWrite(CSRWrite),
    .mretD(mretD),
    .wfiD(wfiD),
    .ecallD(ecallD),
    .ebreakD(ebreakD),
    .IllegalInstrD(IllegalInstrD),
    .FenceID(FenceID)
);

datapath #(RESET_PC) dp (
    .clk(HCLK),
    .reset(~HRESETn),
    .ResultSrc(ResultSrc),
    .ALUSrc(ALUSrc),
    .RegWrite(RegWrite),
    .MemWrite(MemWrite),
    .ImmSrc(ImmSrc),
    .ALUControl(ALUControl),
    .Branch(Branch),
    .Jump(Jump),
    .Jalr(Jalr),
    .CSRRead(CSRRead),
    .CSRWrite(CSRWrite),
    .mretD(mretD),
    .wfiD(wfiD),
    .ecallD(ecallD),
    .ebreakD(ebreakD),
    .IllegalInstrD(IllegalInstrD),
    .FenceID(FenceID),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .HWSTRB(HWSTRB),
    .HWRITE(HWRITE),
    .HSIZE(HSIZE),
    .HBURST(HBURST),
    .HPROT(HPROT),
    .HTRANS(HTRANS),
    .HMASTLOCK(HMASTLOCK),
    .HRDATA(HRDATA),
    .HREADY(HREADY),
    .HRESP(HRESP),
    .PC(PC),
    .InstrD(InstrD),
    .ResultW(Result),
    .PCW(PCW),
    .ALUResultW(ALUResultW),
    .WriteDataW(WriteDataW),
    .MTimerInt(MTimerInt),
    .MSwInt(MSwInt),
    .MExtInt(MExtInt),
    .MTIME_CLINT(MTIME_CLINT),
    .ExternalStall(ExternalStall),
    .InstrRetired(InstrRetired),
    .TrapM(TrapM),
    .mretM_out(mretM)
);

endmodule
