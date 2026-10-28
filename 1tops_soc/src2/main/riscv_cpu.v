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
    output            mretM,

    // Post-Mortem Debug Interface
    input      [ 4:0] dbg_rf_raddr,
    output     [31:0] dbg_rf_rdata,
    output     [31:0] dbg_PCD,
    output     [31:0] dbg_PCE,
    output     [31:0] dbg_PCM,
    output     [31:0] dbg_InstrM,
    output     [31:0] dbg_TrapCauseM,
    output     [31:0] dbg_TrapValM,
    output     [31:0] dbg_mstatus,
    output     [31:0] dbg_mcause,
    output     [31:0] dbg_mtval,
    output     [31:0] dbg_mepc,
    output     [31:0] dbg_mtvec,
    output     [31:0] dbg_mie,
    output     [31:0] dbg_mip,
    output     [31:0] dbg_mscratch,
    output     [63:0] dbg_cycle_cnt,
    output     [63:0] dbg_instret_cnt,
    output     [ 4:0] dbg_stall_flags,
    output     [ 2:0] dbg_flush_flags
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
    .mretM_out(mretM),
    .dbg_rf_raddr(dbg_rf_raddr),
    .dbg_rf_rdata(dbg_rf_rdata),
    .dbg_PCD(dbg_PCD),
    .dbg_PCE(dbg_PCE),
    .dbg_PCM(dbg_PCM),
    .dbg_InstrM(dbg_InstrM),
    .dbg_TrapCauseM(dbg_TrapCauseM),
    .dbg_TrapValM(dbg_TrapValM),
    .dbg_mstatus(dbg_mstatus),
    .dbg_mcause(dbg_mcause),
    .dbg_mtval(dbg_mtval),
    .dbg_mepc(dbg_mepc),
    .dbg_mtvec(dbg_mtvec),
    .dbg_mie(dbg_mie),
    .dbg_mip(dbg_mip),
    .dbg_mscratch(dbg_mscratch),
    .dbg_cycle_cnt(dbg_cycle_cnt),
    .dbg_instret_cnt(dbg_instret_cnt),
    .dbg_stall_flags(dbg_stall_flags),
    .dbg_flush_flags(dbg_flush_flags)
);

endmodule
