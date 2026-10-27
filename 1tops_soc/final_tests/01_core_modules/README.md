# Subsystem 01: Core Modules Unit Tests

## Overview
This subsystem provides standalone, self-checking unit testbenches for the fundamental datapath execution components of the RV32 core. Rather than full UVM overhead, this layer uses deterministic and corner-case directed verification to validate arithmetic, comparisons, sign-extensions, and byte alignments at the lowest hardware primitive level.

---

## Modules Tested

| Module | RTL File | Testbench | Verification Scope |
| :--- | :--- | :--- | :--- |
| **ALU** | [`components/alu.v`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/components/alu.v) | `tb/tb_alu_ops.sv` | ADD, SUB, AND, OR, XOR, SLT (signed), SLTU (unsigned), SLL, SRL, SRA, zero-flag, and overflow detection. |
| **Branching Unit** | [`components/branching_unit.v`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/components/branching_unit.v) | `tb/tb_branching_unit.sv` | BEQ, BNE, BLT, BGE, BLTU, BGEU comparison decisions. |
| **Immediate Extender** | [`components/imm_extend.v`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/components/imm_extend.v) | `tb/tb_imm_extend.sv` | I-type, S-type, B-type, and J-type bit rearrangements and sign-extension. |
| **Subword Unit** | [`components/subword_unit.v`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/components/subword_unit.v) | `tb/tb_subword_unit.sv` | SB/SH/SW byte strobes (`HWSTRB`), store data replication, and LB/LBU/LH/LHU/LW sign/zero extensions. |
| **SHA-256 Module** | `soc_tests/module_level/crypto_sha/sha256.sv` | `tb_sha256.sv` | NIST cryptographic test vectors for 256-bit hashing block. |
| **SHA-512 Module** | `soc_tests/module_level/crypto_sha/sha512.sv` | `tb_sha512.sv` | NIST cryptographic test vectors for 512-bit hashing block. |

---

## How to Run the Tests

Execute tests from this directory using QuestaSim:

```bash
# Run all unit tests
make test_all

# Run individual module tests
make test_alu       # ALU arithmetic, logical, and shift operations
make test_branch    # Branch conditions
make test_imm       # Immediate extension
make test_subword   # Subword load/store byte strobes
make test_sha256    # SHA-256 accelerator
make test_sha512    # SHA-512 accelerator

# Clean simulation artifacts
make clean
```

All test targets compile fresh libraries into a temporary directory to guarantee no stale simulation artifacts are used.
