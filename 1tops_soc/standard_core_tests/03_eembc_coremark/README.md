# Suite 03: EEMBC CoreMark 1.0 Benchmark (CPU Core Only)

## Overview
**EEMBC CoreMark 1.0** is the semiconductor industry's premier embedded CPU core benchmarking standard. Designed by the Embedded Microprocessor Benchmark Consortium (EEMBC), CoreMark measures CPU performance, instruction throughput, and pipeline efficiency while eliminating dependence on compiler library optimizations.

CoreMark tests core capabilities across four algorithmic workloads:
1. **List Processing**: Linked-list insertion, search, and sorting.
2. **Matrix Manipulation**: Multi-dimensional matrix multiplications and LU decomposition.
3. **State Machine**: Mealy and Moore state machine transitions processing text streams.
4. **16-bit CRC Calculation**: Cyclic Redundancy Check verifying computational integrity.

---

## Pure Core Implementation & Zero Uncore Overhead
In this setup, `riscv_cpu` runs CoreMark **directly against a single-cycle AHB-Lite synchronous RAM** without uncore peripherals (UART, APB bridge, GPIO, PLIC, CLINT):
- **Console I/O**: Implemented via memory-mapped character mailbox at `0x80001000`. The testbench intercepts writes and streams formatted text in real-time.
- **Completion & Status**: Upon completion, the CPU writes `1` to `0x80001004` (`tohost`), triggering benchmark verification and cycle accounting.
- **Hardware Performance Counters**: Uses RISC-V hardware CSRs `rdcycle` (`csrr a0, cycle`) and `rdinstret` (`csrr a0, instret`) to measure exact hardware execution metrics.

---

## Directory Structure
```
03_eembc_coremark/
├── bsp/
│   ├── crt.S                # Bootloader initializing SP, GP, clearing BSS, entering main
│   ├── link.ld              # Memory map placing 2 MB RAM at 0x80000000
│   └── syscalls.c           # Memory-mapped console I/O, CSR cycle reading, formatted printf
├── src/
│   ├── core_main.c          # CoreMark driver and harness
│   ├── core_list_join.c     # Linked list benchmark workload
│   ├── core_matrix.c        # Matrix manipulation workload
│   ├── core_state.c         # State machine workload
│   ├── core_util.c          # Math, string parsing, and CRC utilities
│   ├── coremark.h           # CoreMark declarations and configurations
│   ├── core_portme.c        # Hardware porting layer & performance reporter
│   └── core_portme.h        # Platform configuration
├── tb_core_coremark.sv      # Pure core testbench streaming console output
├── run_coremark.py          # Automated compilation, simulation runner, and reporter
├── Makefile                 # Make target runner
└── README.md                # Documentation
```

---

## Hardware Execution Results (Pure riscv_cpu Core)
When executed on the 5-stage pipelined RV32I core:
- **Total Benchmark Cycles**: ~204,641 cycles (1 iteration)
- **Total Instructions Done**: ~132,530 instructions
- **Core CPI (Cycles Per Instruction)**: **1.54**
- **Core IPC (Instructions Per Cycle)**: **0.64**
- **Elapsed Simulation Time**: ~23 seconds in QuestaSim

---

## How to Run

### Run CoreMark
```bash
make run
# or
python3 run_coremark.py --iterations 1
```

### Clean Artifacts
```bash
make clean
```
