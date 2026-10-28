// =============================================================================
// Module: datapath
// Purpose: Pipelined Datapath with Integrated AHB IFU/LSU and EBU Arbiter
// =============================================================================

module datapath #(parameter RESET_PC = 32'h0000_0000) (
    input         clk, reset,
    input  [2:0]  ResultSrc,
    input         ALUSrc, RegWrite, MemWrite,
    input  [1:0]  ImmSrc,
    input  [3:0]  ALUControl,
    input         Branch, Jump, Jalr,
    input         CSRRead, CSRWrite,
    input         mretD, wfiD, ecallD, ebreakD, IllegalInstrD,
    input         FenceID,

    // Unified AHB-Lite Master Bus Interface
    output [31:0] HADDR,
    output [31:0] HWDATA,
    output [ 3:0] HWSTRB,
    output        HWRITE,
    output [ 2:0] HSIZE,
    output [ 2:0] HBURST,
    output [ 3:0] HPROT,
    output [ 1:0] HTRANS,
    output        HMASTLOCK,
    input  [31:0] HRDATA,
    input         HREADY,
    input         HRESP,

    // Instruction and Writeback Monitor
    output [31:0] PC,
    output [31:0] InstrD,
    output [31:0] ResultW,
    output [31:0] PCW, ALUResultW, WriteDataW,

    // Hardware Interrupt Lines
    input         MTimerInt,
    input         MSwInt,
    input         MExtInt,
    input  [63:0] MTIME_CLINT,

    // External Stall from Debugger / Step Controller
    input         ExternalStall,

    // Instruction Retired 1-cycle pulse
    output        InstrRetired,

    // Trap Monitoring Outputs
    output        TrapM,
    output        mretM_out,

    // Post-Mortem Debug Interface
    input  [4:0]  dbg_rf_raddr,
    output [31:0] dbg_rf_rdata,
    output [31:0] dbg_PCD,
    output [31:0] dbg_PCE,
    output [31:0] dbg_PCM,
    output [31:0] dbg_InstrM,
    output [31:0] dbg_TrapCauseM,
    output [31:0] dbg_TrapValM,
    output [31:0] dbg_mstatus,
    output [31:0] dbg_mcause,
    output [31:0] dbg_mtval,
    output [31:0] dbg_mepc,
    output [31:0] dbg_mtvec,
    output [31:0] dbg_mie,
    output [31:0] dbg_mip,
    output [31:0] dbg_mscratch,
    output [63:0] dbg_cycle_cnt,
    output [63:0] dbg_instret_cnt,
    output [4:0]  dbg_stall_flags,
    output [2:0]  dbg_flush_flags
);

wire [31:0] PCPlus4, PCTargetE, AuiPC, lAuiPC, lAuiPCM, lAuiPCW;
wire [31:0] ImmExtD, ImmExtE;
wire [31:0] PCD, PCPlus4D, PCPlus4E, PCPlus4M, PCPlus4W, PCM, PCE;
wire [31:0] ReadData1, ReadData2, ReadData1E, ReadData2E, ReadDataW, WriteDataE, WriteDataM, ALUResultE, ALUResultM;
wire [31:0] SrcAE, SrcBE;
wire [19:0] InstrE_31_12;
wire [4:0]  Rs1E, Rs2E, RdE, RdM, RdW;
wire [3:0]  ALUControlE;
wire [2:0]  funct3E, funct3M;
wire [2:0]  ResultSrcE, ResultSrcM, ResultSrcW;
wire        Zero, Less, LessU, TakeBranch, InstrE_5;
wire        RegWriteE, MemWriteE, JumpE, JalrE, BranchE, ALUSrcE;
wire        FenceIE;
wire        RegWriteM;
wire        MemWriteM_raw;
wire        RegWriteW;
wire        StallF, StallD, StallE, StallM, StallW, FlushE, FlushD, FlushM;
wire [1:0]  ForwardAE, ForwardBE;

// CSR & Trap Signals
wire        CSRReadE, CSRWriteE;
wire [31:0] SrcAM;
wire [4:0]  uimmM;
wire [11:0] CSRAdrM;
wire        CSRReadM, CSRWriteM;
wire [31:0] CSRReadValM, CSRReadValW;
wire        mretE, wfiE, ecallE, ebreakE, IllegalInstrE;
wire        mretM, wfiM, ecallM, ebreakM, IllegalInstrM;
wire [31:0] InstrE, InstrM;

wire [31:0] mstatus, mie, mip, mtvec, mepc;
wire [31:0] TrapCauseM, TrapValM, TrapVectorM;
wire        InterruptM, IntPendingM;

assign mretM_out = mretM;

wire PCSrcE = ((BranchE & TakeBranch) || JumpE || JalrE || FenceIE) ? 1'b1 : 1'b0;

// =========================================================================
// FETCH STAGE (F)
// =========================================================================
reg [31:0] PCNextF;
always @(*) begin
    if (TrapM)
        PCNextF = TrapVectorM;
    else if (mretM)
        PCNextF = mepc;
    else if (FenceIE)
        PCNextF = PCPlus4E;
    else if (JalrE)
        PCNextF = ALUResultE;
    else if (PCSrcE)
        PCNextF = PCTargetE;
    else
        PCNextF = PCPlus4;
end

reset_ff #(32, RESET_PC) pcreg(clk, reset, StallF, PCNextF, PC);
adder #(32) pcadd4(PC, 32'd4, PCPlus4);

// AHB Instruction Fetch Interface (IFU)
wire [31:0] IFU_Instr;
wire [31:0] IFUHADDR;
wire [ 1:0] IFUHTRANS;
wire [ 2:0] IFUHSIZE;
wire        IFUHREADY;
wire        IFUStallF;
wire [31:0] PC_IFU;
wire        IFU_DataPhase;

ahbinterface #(1'b0) ifu_bus (
    .HCLK(clk),
    .HRESETn(~reset),
    .Flush(FlushD),
    .Stall(StallD),
    .Req(~reset),
    .Write(1'b0),
    .Addr(PC),
    .Size(3'b010), // Word (32-bit)
    .ByteMask(4'b1111),
    .WriteData(32'd0),
    .FetchBuffer(IFU_Instr),
    .BusStall(IFUStallF),
    .Addr_DataPhase(PC_IFU),
    .DataPhase(IFU_DataPhase),
    .HTRANS(IFUHTRANS),
    .HWRITE(),
    .HADDR(IFUHADDR),
    .HSIZE(IFUHSIZE),
    .HWDATA(),
    .HWSTRB(),
    .HRDATA(HRDATA),
    .HREADY(IFUHREADY)
);

wire ValidD, ValidE, ValidM;

// Pipeline Register: F -> D
pl_reg_fd plfd(clk, reset, StallD, FlushD, IFU_DataPhase, IFU_Instr, PC_IFU, PC_IFU + 32'd4, InstrD, PCD, PCPlus4D, ValidD);

adder #(32) pcaddbranch(PCE, ImmExtE, PCTargetE);

// =========================================================================
// DECODE STAGE (D)
// =========================================================================
reg_file   rf(clk, RegWriteW, InstrD[19:15], InstrD[24:20], RdW, ResultW, ReadData1, ReadData2, dbg_rf_raddr, dbg_rf_rdata);
imm_extend ext(InstrD[31:7], ImmSrc, ImmExtD);

wire uses_rs1D = (InstrD[6:0] != 7'b0110111) && (InstrD[6:0] != 7'b0010111) && (InstrD[6:0] != 7'b1101111);
wire uses_rs2D = (InstrD[6:0] == 7'b0110011) || (InstrD[6:0] == 7'b0100011) || (InstrD[6:0] == 7'b1100011);
wire [4:0] Rs1D_eff = uses_rs1D ? InstrD[19:15] : 5'd0;
wire [4:0] Rs2D_eff = uses_rs2D ? InstrD[24:20] : 5'd0;

// Pipeline Register: D -> E
pl_reg_de plde(
    .clk(clk), .reset(reset), .clr(FlushE), .StallE(StallE),
    .RegWriteD(RegWrite), .MemWriteD(MemWrite), .JumpD(Jump), .JalrD(Jalr), .BranchD(Branch), .ALUSrcD(ALUSrc),
    .ResultSrcD(ResultSrc), .ALUControlD(ALUControl),
    .ReadData1D(ReadData1), .ReadData2D(ReadData2),
    .PCD(PCD), .PCPlus4D(PCPlus4D),
    .Rs1D(Rs1D_eff), .Rs2D(Rs2D_eff), .RdD(InstrD[11:7]),
    .ImmExtD(ImmExtD), .funct3D(InstrD[14:12]),
    .InstrD_31_12(InstrD[31:12]), .InstrD_5(InstrD[5]),
    .CSRReadD(CSRRead), .CSRWriteD(CSRWrite),
    .mretD(mretD), .wfiD(wfiD), .ecallD(ecallD), .ebreakD(ebreakD), .IllegalInstrD(IllegalInstrD),
    .FenceID(FenceID),
    .ValidD(ValidD),
    .InstrD(InstrD),
    .RegWriteE(RegWriteE), .MemWriteE(MemWriteE), .JumpE(JumpE), .JalrE(JalrE), .BranchE(BranchE), .ALUSrcE(ALUSrcE),
    .ResultSrcE(ResultSrcE), .ALUControlE(ALUControlE),
    .ReadData1E(ReadData1E), .ReadData2E(ReadData2E),
    .PCE(PCE), .PCPlus4E(PCPlus4E),
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdE(RdE),
    .ImmExtE(ImmExtE), .funct3E(funct3E),
    .InstrE_31_12(InstrE_31_12), .InstrE_5(InstrE_5),
    .CSRReadE(CSRReadE), .CSRWriteE(CSRWriteE),
    .mretE(mretE), .wfiE(wfiE), .ecallE(ecallE), .ebreakE(ebreakE), .IllegalInstrE(IllegalInstrE),
    .FenceIE(FenceIE),
    .ValidE(ValidE),
    .InstrE(InstrE)
);

// =========================================================================
// EXECUTE STAGE (E)
// =========================================================================
wire [31:0] ResultM;
mux5 #(32)  resmuxM(ALUResultM, 32'b0, PCPlus4M, lAuiPCM, CSRReadValM, ResultSrcM, ResultM);

mux3 #(32) FAE(ReadData1E, ResultW, ResultM, ForwardAE, SrcAE);
mux3 #(32) FBE(ReadData2E, ResultW, ResultM, ForwardBE, WriteDataE);

mux2 #(32) srcbmux(WriteDataE, ImmExtE, ALUSrcE, SrcBE);
alu        alu_inst(SrcAE, SrcBE, ALUControlE, ALUResultE, Zero, Less, LessU);

adder #(32) auipcadder({InstrE_31_12, 12'b0}, PCE, AuiPC);
mux2  #(32) lauipcmux(AuiPC, {InstrE_31_12, 12'b0}, InstrE_5, lAuiPC);

branching_unit bu(funct3E, Zero, Less, LessU, TakeBranch);

// Pipeline Register: E -> M
pl_reg_em plem(
    .clk(clk), .reset(reset), .clr(FlushM), .StallM(StallM),
    .RegWriteE(RegWriteE), .MemWriteE(MemWriteE),
    .ResultSrcE(ResultSrcE),
    .ALUResultE(ALUResultE), .WriteDataE(WriteDataE), .PCPlus4E(PCPlus4E),
    .RdE(RdE), .PCE(PCE), .lAuiPCE(lAuiPC), .funct3E(funct3E),
    .SrcAE(SrcAE), .uimmE(Rs1E), .CSRAdrE(InstrE_31_12[19:8]),
    .CSRReadE(CSRReadE), .CSRWriteE(CSRWriteE),
    .mretE(mretE), .wfiE(wfiE), .ecallE(ecallE), .ebreakE(ebreakE), .IllegalInstrE(IllegalInstrE),
    .ValidE(ValidE),
    .InstrE(InstrE),
    .RegWriteM(RegWriteM), .MemWriteM(MemWriteM_raw),
    .ResultSrcM(ResultSrcM),
    .ALUResultM(ALUResultM), .WriteDataM(WriteDataM), .PCPlus4M(PCPlus4M),
    .RdM(RdM), .PCM(PCM), .lAuiPCM(lAuiPCM), .funct3M(funct3M),
    .SrcAM(SrcAM), .uimmM(uimmM), .CSRAdrM(CSRAdrM),
    .CSRReadM(CSRReadM), .CSRWriteM(CSRWriteM),
    .mretM(mretM), .wfiM(wfiM), .ecallM(ecallM), .ebreakM(ebreakM), .IllegalInstrM(IllegalInstrM),
    .ValidM(ValidM),
    .InstrM(InstrM)
);

// =========================================================================
// MEMORY STAGE (M) — AHB Load/Store Unit & CSR / Trap
// =========================================================================
wire MemWriteM_gated = MemWriteM_raw & ~TrapM;
wire MemReadM = (ResultSrcM == 3'b001); // ResultSrc = Load

// AHB Load/Store Interface (LSU)
wire [31:0] LSU_RawReadData;
wire [31:0] LSUHADDR;
wire [ 1:0] LSUHTRANS;
wire        LSUHWRITE;
wire [ 2:0] LSUHSIZE;
wire [31:0] LSUHWDATA;
wire [ 3:0] LSUHWSTRB;
wire        LSUHREADY;
wire        LSUStallM;

// Subword Processing Unit: Handles Byte Mask Generation, Store Data Replication,
// and Load Data Alignment & Sign/Zero Extension
wire [ 3:0] LSUHWSTRB_gen;
wire [31:0] LSUWriteDataM;
wire [31:0] ReadDataM;

subword_unit subword_inst (
    .funct3(funct3M),
    .byte_offset(ALUResultM[1:0]),
    .write_data_in(WriteDataM),
    .raw_read_data(LSU_RawReadData),
    .byte_mask(LSUHWSTRB_gen),
    .write_data_out(LSUWriteDataM),
    .read_data_out(ReadDataM)
);

ahbinterface #(1'b1) lsu_bus (
    .HCLK(clk),
    .HRESETn(~reset),
    .Flush(TrapM),
    .Stall(1'b0),
    .Req(MemWriteM_gated | MemReadM),
    .Write(MemWriteM_gated),
    .Addr(ALUResultM),
    .Size({1'b0, funct3M[1:0]}),
    .ByteMask(LSUHWSTRB_gen),
    .WriteData(LSUWriteDataM),
    .FetchBuffer(LSU_RawReadData),
    .BusStall(LSUStallM),
    .Addr_DataPhase(),
    .DataPhase(),
    .HTRANS(LSUHTRANS),
    .HWRITE(LSUHWRITE),
    .HADDR(LSUHADDR),
    .HSIZE(LSUHSIZE),
    .HWDATA(LSUHWDATA),
    .HWSTRB(LSUHWSTRB),
    .HRDATA(HRDATA),
    .HREADY(LSUHREADY)
);

// External Bus Unit: Arbitrates IFU and LSU onto Unified AHB Master Bus
ebu ebu_inst (
    .HCLK(clk),
    .HRESETn(~reset),
    .IFUHADDR(IFUHADDR),
    .IFUHTRANS(IFUHTRANS),
    .IFUHSIZE(IFUHSIZE),
    .IFUHREADY(IFUHREADY),
    .LSUHADDR(LSUHADDR),
    .LSUHTRANS(LSUHTRANS),
    .LSUHWRITE(LSUHWRITE),
    .LSUHSIZE(LSUHSIZE),
    .LSUHWDATA(LSUHWDATA),
    .LSUHWSTRB(LSUHWSTRB),
    .LSUHREADY(LSUHREADY),
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
    .HRESP(HRESP)
);

// CSR File
csr_file csr_inst (
    .clk(clk),
    .reset(reset),
    .CSRAdrM(CSRAdrM),
    .CSRWriteM(CSRWriteM & ~TrapM),
    .CSRReadM(CSRReadM),
    .Funct3M(funct3M),
    .uimmM(uimmM),
    .SrcAM(SrcAM),
    .TrapM(TrapM),
    .mretM(mretM),
    .TrapCauseM(TrapCauseM),
    .TrapValM(TrapValM),
    .PCM(PCM),
    .MTimerInt(MTimerInt),
    .MSwInt(MSwInt),
    .MExtInt(MExtInt),
    .MTIME_CLINT(MTIME_CLINT),
    .CSRReadValM(CSRReadValM),
    .mstatus(mstatus),
    .mie(mie),
    .mip(mip),
    .mtvec(mtvec),
    .mepc(mepc),
    .mcause_out(dbg_mcause),
    .mtval_out(dbg_mtval),
    .mscratch_out(dbg_mscratch),
    .cycle_cnt_out(dbg_cycle_cnt),
    .instret_cnt_out(dbg_instret_cnt),
    .ValidM(ValidM)
);

// Trap Unit
trap_unit tu (
    .IllegalInstrM(IllegalInstrM),
    .BreakpointFaultM(ebreakM),
    .EcallFaultM(ecallM),
    .InstrMisalignedM(1'b0),
    .PCM(PCM),
    .InstrM(InstrM),
    .mstatus(mstatus),
    .mie(mie),
    .mip(mip),
    .mtvec(mtvec),
    .TrapM(TrapM),
    .InterruptM(InterruptM),
    .IntPendingM(IntPendingM),
    .TrapCauseM(TrapCauseM),
    .TrapValM(TrapValM),
    .TrapVectorM(TrapVectorM)
);

// Pipeline Register: M -> W
wire ValidW;
pl_reg_mw plmw(
    .clk(clk), .reset(reset), .StallW(StallW),
    .RegWriteM(RegWriteM & ~TrapM),
    .ResultSrcM(ResultSrcM),
    .ALUResultM(ALUResultM),
    .ReadDataM(ReadDataM),
    .PCPlus4M(PCPlus4M),
    .RdM(RdM),
    .PCM(PCM),
    .WriteDataM(WriteDataM),
    .lAuiPCM(lAuiPCM),
    .CSRReadValM(CSRReadValM),
    .ValidM(ValidM & ~TrapM),
    .RegWriteW(RegWriteW),
    .ResultSrcW(ResultSrcW),
    .ALUResultW(ALUResultW),
    .ReadDataW(ReadDataW),
    .PCPlus4W(PCPlus4W),
    .RdW(RdW),
    .PCW(PCW),
    .WriteDataW(WriteDataW),
    .lAuiPCW(lAuiPCW),
    .CSRReadValW(CSRReadValW),
    .ValidW(ValidW)
);

// Instruction Retired: 1-cycle active-high pulse asserted when an instruction cleanly commits to Writeback
// Exactly matches OpenHW Wally: InstrValidM & ~StallW & ~FlushW (where FlushWCause = TrapM)
assign InstrRetired = ValidM & ~StallW & ~TrapM;

// =========================================================================
// WRITEBACK STAGE (W)
// =========================================================================
mux5 #(32) resultmux(ALUResultW, ReadDataW, PCPlus4W, lAuiPCW, CSRReadValW, ResultSrcW, ResultW);

// Hazard Unit
hazard hazardunit(
    .Rs1D(Rs1D_eff), .Rs2D(Rs2D_eff),
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdE(RdE),
    .RdM(RdM), .RdW(RdW),
    .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
    .ResultSrcE(ResultSrcE),
    .PCSrcE(PCSrcE),
    .TrapM(TrapM),
    .mretM(mretM),
    .LSUStallM(LSUStallM),
    .IFUStallF(IFUStallF),
    .ExternalStall(ExternalStall),
    .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
    .StallF(StallF), .StallD(StallD), .StallE(StallE), .StallM(StallM), .StallW(StallW),
    .FlushD(FlushD), .FlushE(FlushE), .FlushM(FlushM)
);

// Post-Mortem Debug Interface Assignments
assign dbg_PCD         = PCD;
assign dbg_PCE         = PCE;
assign dbg_PCM         = PCM;
assign dbg_InstrM      = InstrM;
assign dbg_TrapCauseM  = TrapCauseM;
assign dbg_TrapValM    = TrapValM;
assign dbg_mstatus     = mstatus;
assign dbg_mepc        = mepc;
assign dbg_mtvec       = mtvec;
assign dbg_mie         = mie;
assign dbg_mip         = mip;
assign dbg_stall_flags = {StallW, StallM, StallE, StallD, StallF};
assign dbg_flush_flags = {FlushM, FlushE, FlushD};

endmodule
