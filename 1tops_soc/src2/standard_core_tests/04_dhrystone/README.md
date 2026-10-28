# Suite 04: Dhrystone 2.1 Benchmark (CPU Core Only)

## Overview
**Dhrystone 2.1** (Reinhold P. Weicker) is the universally recognized integer computing benchmark used throughout the semiconductor and processor design industry to measure:
- **Dhrystones per Second**: Raw loop throughput.
- **DMIPS (Dhrystone MIPS)**: Relative computing performance normalized to the baseline VAX-11/780 (1757 Dhrystones/second = 1 DMIPS).
- **DMIPS/MHz**: Frequency-independent architectural efficiency rating.

Dhrystone exercises integer arithmetic, control logic, string manipulation, pointer indirection, and array indexing representative of typical compiled systems software.

---

## Pure Core Implementation & Zero Uncore Overhead
The benchmark runs on `riscv_cpu` connected directly to single-cycle AHB-Lite synchronous RAM:
- **Memory Console**: Formatted character stream is written to `0x80001000`. The testbench intercepts writes and streams them to the simulation console in real-time.
- **Hardware Performance Counters**: Uses CSR `rdcycle` and `rdinstret` to record cycle count and retired instructions with cycle accuracy.
- **Full Algorithmic Verification**: At the conclusion of execution, the benchmark performs an automated self-check on all global variables (`Int_Glob`, `Bool_Glob`, `Ch_1_Glob`, `Ch_2_Glob`, `Arr_1_Glob`, `Arr_2_Glob`, `Int_1_Loc`, `Int_2_Loc`, `Int_3_Loc`) to confirm 100% computational correctness before writing `1` to `0x80001004` (`tohost`).

---

## Directory Structure
```
04_dhrystone/
├── bsp/
│   ├── crt.S                # Bootloader setting up stack and entering main
│   ├── link.ld              # Memory map placing 2 MB RAM at 0x80000000
│   └── syscalls.c           # Memory console and CSR reading
├── src/
│   ├── dhry_1.c             # Dhrystone 2.1 main loop, driver, and verification
│   ├── dhry_2.c             # Dhrystone procedures and functions
│   └── dhry.h               # Configuration and data structure declarations
├── tb_core_dhrystone.sv     # Pure core testbench streaming console output
├── run_dhrystone.py         # Automated compiler, simulator, and reporter
├── Makefile                 # Make target runner
└── README.md                # Documentation
```

---

## Benchmark Results (5-Stage Pipelined RV32I Core @ 50 MHz)
- **Number of Runs**: 100 iterations
- **Total Benchmark Cycles**: 79,565 cycles
- **Total Instructions**: 51,160 instructions
- **Core CPI**: **1.55**
- **Core IPC**: **0.64**
- **Cycles per Dhrystone**: **795 cycles**
- **Dhrystones per Second**: **62,893**
- **DMIPS**: **35 DMIPS**
- **DMIPS/MHz**: **0.71 DMIPS/MHz**
- **Verification Status**: **100% PASSED** (All 9 variables matched expected values)
- **Simulation Wall Time**: ~12 seconds in QuestaSim

---

## How to Run

### Run Dhrystone Benchmark
```bash
make run
# or
python3 run_dhrystone.py --runs 100
```

### Clean Artifacts
```bash
make clean
```
