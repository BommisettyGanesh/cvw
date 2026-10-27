// =============================================================================
// Module: riscv_pipelined
// Purpose: Top-level simulation wrapper integrating memories and CPU core
// =============================================================================

module riscv_pipelined (
    input         clk, reset,
    input         Ext_MemWrite,
    input  [31:0] Ext_WriteData, Ext_DataAdr,
    output        MemWrite,
    output [31:0] WriteData, DataAdr, ReadData,
    output [31:0] PCW, Result, ALUResultW, WriteDataW
);

wire [31:0] Instr, PC;
wire [31:0] DataAdr_rv32, WriteData_rv32;
wire [ 2:0] Store, funct3;
wire        MemWrite_rv32;
wire        TrapM;

// Simple internal 64-bit cycle counter for MTIME when uncore is absent
reg [63:0]  internal_mtime;
always @(posedge clk) begin
    if (reset)
        internal_mtime <= 64'd0;
    else
        internal_mtime <= internal_mtime + 64'd1;
end

// Instantiate processor core
riscv_cpu rvcpu (
    .clk(clk),
    .reset(reset),
    .PC(PC),
    .Instr(Instr),
    .MemWriteM(MemWrite_rv32),
    .Mem_WrAddr(DataAdr_rv32),
    .Mem_WrData(WriteData_rv32),
    .ReadData(ReadData),
    .Result(Result),
    .funct3(funct3),
    .PCW(PCW),
    .ALUResultW(ALUResultW),
    .WriteDataW(WriteDataW),
    .MTimerInt(1'b0),
    .MSwInt(1'b0),
    .MExtInt(1'b0),
    .MTIME_CLINT(internal_mtime),
    .TrapM(TrapM),
    .mretM()
);

instr_mem instrmem (PC, Instr);
data_mem  datamem  (clk, MemWrite, Store, DataAdr, WriteData, ReadData);

assign Store     = (Ext_MemWrite && reset) ? 3'b010 : funct3;
assign MemWrite  = (Ext_MemWrite && reset) ? 1'b1 : MemWrite_rv32;
assign WriteData = (Ext_MemWrite && reset) ? Ext_WriteData : WriteData_rv32;
assign DataAdr   = reset ? Ext_DataAdr : DataAdr_rv32;

endmodule
