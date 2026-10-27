# Suite 02: UC Berkeley riscv-tests (CPU Core Only)

## Overview
The **UC Berkeley `riscv-tests`** suite (`isa/rv32ui`) is the foundational self-checking unit test framework created by the original RISC-V designers at the University of California, Berkeley.

Unlike architectural signature comparison which requires a separate golden simulator trace, Berkeley tests are **fully autonomous and self-checking in hardware**. Each test executes a sequence of micro-assertions directly on the pipeline and writes results to the standard `tohost` memory-mapped register.

---

## Pass / Fail Protocol (`tohost`)
In the Berkeley test protocol:
1. When all assertions in a test pass:
   - The test stores integer `1` to `tohost`:
   ```assembly
   pass:
     li a0, 1
     la t0, tohost
     sw a0, 0(t0)
   1: j 1b
   ```
2. When an assertion fails:
   - The test stores `(testnum << 1) | 1` to `tohost`:
   ```assembly
   fail:
     slli a0, gp, 1
     ori  a0, a0, 1
     la   t0, tohost
     sw   a0, 0(t0)
   1: j 1b
   ```
3. The testbench (`tb_core_berkeley.sv`) monitors writes to `tohost`:
   - If `HWDATA == 1`: Reports `[PASS]` along with cycle count, retired instructions, and calculated CPI.
   - If `HWDATA > 1`: Reports `[FAIL]` and decodes the exact failing assertion ID (`HWDATA >> 1`).

---

## Directory Structure
```
02_berkeley_riscv_tests/
├── env/
│   ├── link.ld              # Linker script mapping text to 0x80000000 and .tohost section
│   ├── riscv_test.h         # Standard Berkeley test environment macros
│   └── test_macros.h        # Self-checking assertion macros (TEST_RR_OP, TEST_BR_OP, etc.)
├── src/                     # Self-checking assembly tests
│   ├── rv32ui-p-add.S       # Register-register arithmetic
│   ├── rv32ui-p-addi.S      # Immediate arithmetic
│   ├── rv32ui-p-sub.S       # Subtraction
│   ├── rv32ui-p-and.S       # Bitwise AND
│   ├── rv32ui-p-or.S        # Bitwise OR
│   ├── rv32ui-p-xor.S       # Bitwise XOR
│   ├── rv32ui-p-sll.S       # Shift left logical
│   ├── rv32ui-p-srl.S       # Shift right logical
│   ├── rv32ui-p-sra.S       # Shift right arithmetic
│   ├── rv32ui-p-slt.S       # Set less than (signed)
│   ├── rv32ui-p-sltu.S      # Set less than (unsigned)
│   ├── rv32ui-p-lui.S       # Load upper immediate
│   ├── rv32ui-p-auipc.S     # Add upper immediate to PC
│   ├── rv32ui-p-beq.S       # Branch equal
│   ├── rv32ui-p-bne.S       # Branch not equal
│   ├── rv32ui-p-blt.S       # Branch less than
│   ├── rv32ui-p-bge.S       # Branch greater than or equal
│   ├── rv32ui-p-jal.S       # Jump and link
│   ├── rv32ui-p-jalr.S      # Jump and link register
│   ├── rv32ui-p-lw.S        # Load word
│   ├── rv32ui-p-sw.S        # Store word
│   └── rv32ui-p-hazard.S    # Pipeline RAW, forwarding, load-use delays, WAW
├── tb_core_berkeley.sv      # Pure core testbench monitoring tohost
├── run_berkeley_tests.py    # Automated test runner and reporting script
├── generate_berkeley_tests.py # Source test generator
├── Makefile                 # Make automation
└── README.md                # Documentation
```

---

## How to Run

### Run All 22 Tests
```bash
make test_all
# or
python3 run_berkeley_tests.py --group all
```

### Run by Category
```bash
make test_alu       # 13 ALU tests (add, sub, and, or, xor, shifts, slt, lui, auipc)
make test_branch    # 6 Branch & Jump tests (beq, bne, blt, bge, jal, jalr)
make test_memory    # Load/Store memory tests (lw, sw)
make test_hazard    # Pipeline hazard & forwarding stress test
```

### Clean Stale Files
```bash
make clean
```
