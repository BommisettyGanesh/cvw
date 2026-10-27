//-----------------------------------------------------------------------------
// Accelerator Debug Memory Map & Register Definitions
// For CORE-V Wally / 1tops_soc Accelerator Space (EXT_MEM_BASE = 0x30000000)
// Total Space: 16 Megabytes (0x30000000 - 0x30FFFFFF)
//-----------------------------------------------------------------------------

`ifndef ACCELERATOR_DEBUG_DEF_VH
`define ACCELERATOR_DEBUG_DEF_VH

// Base and Range Definitions
`define ACC_BASE_ADDR              32'h3000_0000
`define ACC_RANGE_MASK             32'h00FF_FFFF

//-----------------------------------------------------------------------------
// 1. Current Dummy Multiplier Accelerator (multiplier_ahb.sv)
//-----------------------------------------------------------------------------
`define ACC_DUMMY_REG_OP_A         32'h3000_0000  // [31:0] Operand A (R/W)
`define ACC_DUMMY_REG_OP_B         32'h3000_0004  // [31:0] Operand B (R/W)
`define ACC_DUMMY_REG_PRODUCT      32'h3000_0008  // [31:0] Product Result (RO)
`define ACC_DUMMY_REG_CONSOLE      32'h3000_000C  // [7:0]  Console Print Char (WO)

//-----------------------------------------------------------------------------
// 2. Memory Map Allocation for Upcoming Larger Accelerator (e.g. 1TOPS / CTM)
//-----------------------------------------------------------------------------
// Region A: Control & Status Registers (4 KB: 0x3000_0000 - 0x3000_0FFF)
`define ACC_CSR_BASE               32'h3000_0000
`define ACC_REG_CTRL               32'h3000_0000  // Bit 0: Start, Bit 1: Soft Reset, Bit 2: IRQ Enable
`define ACC_REG_STATUS             32'h3000_0004  // Bit 0: Busy, Bit 1: Done, Bit 2: Error
`define ACC_REG_CONFIG             32'h3000_0008  // Accelerator mode, precision, batch size
`define ACC_REG_CYCLES             32'h3000_000C  // Cycle execution counter
`define ACC_REG_INPUT_LEN          32'h3000_0010  // Input buffer length in words
`define ACC_REG_OUTPUT_LEN         32'h3000_0014  // Output buffer length in words
`define ACC_REG_WEIGHT_LEN         32'h3000_0018  // Weight buffer length in words
`define ACC_REG_VERSION            32'h3000_001C  // Hardware Accelerator Version ID

// Region B: Input Activations Buffer (~1 MB: 0x3000_1000 - 0x300F_FFFF)
`define ACC_INPUT_BUF_BASE         32'h3000_1000
`define ACC_INPUT_BUF_LIMIT        32'h300F_FFFF

// Region C: Model Weights / Hypervector Memory (~7 MB: 0x3010_0000 - 0x307F_FFFF)
`define ACC_WEIGHT_BUF_BASE        32'h3010_0000
`define ACC_WEIGHT_BUF_LIMIT       32'h307F_FFFF

// Region D: Output Results / Inferences Buffer (~8 MB: 0x3080_0000 - 0x30FF_FFFF)
`define ACC_OUTPUT_BUF_BASE        32'h3080_0000
`define ACC_OUTPUT_BUF_LIMIT       32'h30FF_FFFF

`endif // ACCELERATOR_DEBUG_DEF_VH
