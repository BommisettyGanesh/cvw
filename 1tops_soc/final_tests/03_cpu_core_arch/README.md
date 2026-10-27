# Subsystem 03: CPU Core Official RISC-V Architectural Verification

## Overview
This subsystem runs the official **RISC-V International Architectural Compliance Test Suite** (`riscv-arch-test`) against our pipelined RV32 core. Rather than ad-hoc waveforms, each test compiles an official compliance test binary, runs it on the golden **Spike / Sail** Instruction Set Simulator (ISS) to generate a reference architectural signature, executes the identical binary on our hardware in QuestaSim, and performs a 100% word-for-word comparison of the retirement memory signature.

---

## Test Suites & Extensions Covered

1. **RV32I Integer Base Instruction Suite**:
   * **Computational**: `addi`, `add`, `sub`, `slt`, `slti`, `sltu`, `sltiu`, `and`, `andi`, `or`, `ori`, `xor`, `xori`, `sll`, `slli`, `srl`, `srli`, `sra`, `srai`, `lui`, `auipc`.
   * **Control Transfer**: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`, `jal`, `jalr`.
   * **Memory Transfers & Alignment**: `lw`, `lh`, `lhu`, `lb`, `lbu`, `sw`, `sh`, `sb` across word, halfword, and unaligned byte offsets.
2. **Zicsr Extension**:
   * Validates full read/write, set-bit, and clear-bit atomic operations (`csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci`) on machine-mode CSRs (`mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`).
3. **Privilege Mode Traps**:
   * Tests synchronous environment calls (`ecall`), software breakpoints (`ebreak`), and pipeline serialization (`fence.i`).

---

## Verification Methodology (Lock-Step Golden Signature Comparison)

```
       [RISC-V Compliance Assembly Source (.S)]
                         │
          ┌──────────────┴──────────────┐
          ▼                             ▼
   [Spike / Sail ISS]         [QuestaSim Hardware RTL]
          │                             │
          ▼                             ▼
[Golden Signature (.sig)]      [DUT Signature (.sig)]
          │                             │
          └──────────────┬──────────────┘
                         ▼
             [Word-by-Word Diff Engine]
                   (100% Match)
```

---

## How to Run the Tests

Execute from this directory:

```bash
# Run the representative architectural test suite
make test_all

# Run specific functional categories
make test_alu_arch     # Integer arithmetic, logical, and shifts
make test_branch_arch  # Conditional branches and jump links
make test_memory_arch  # Byte/halfword/word loads and stores
make test_priv_arch    # ecall, ebreak, fence.i
make test_zicsr_arch   # Machine Control & Status Registers (CSRs)

# Run an individual test directly via the Python runner
python3 ../../riscv_test/run_arch_test.py --test lui-01
python3 ../../riscv_test/run_arch_test.py --test Zicsr-csrrw-00
```
