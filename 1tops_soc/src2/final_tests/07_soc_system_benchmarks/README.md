# Subsystem 07: SoC Top-Level System & Bare-Metal C Benchmarks

This subsystem contains realistic bare-metal C applications and computational benchmarks running on the full 5-stage pipelined RISC-V SoC with integrated AMBA AHB/APB interconnect.

---

## 1. Subsystem Architecture Overview

Programs in this directory run on the complete system:
- **CPU Core**: 5-stage pipelined RV32I processor (`riscv_cpu.v`).
- **Memory**: 2 MB address space (`0x8000_0000 - 0x801F_FFFF`) partitioned into 1 MB Instruction RAM and 1 MB Data RAM.
- **Peripherals**: 16550 UART (character console streaming via memory-mapped I/O at `0x1000_0000`).
- **Hardware Performance Counters**: Real-time cycle and instruction counting via RISC-V `rdcycle` and `rdinstret` CSRs.
- **Board Support Package (BSP)**:
  - Linker Script ([link.ld](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/07_soc_system_benchmarks/bsp/link.ld)): Defines reset vector at `0x8000_0000`, stack setup, data segment initialization, and `.tohost` communication section.
  - Startup Code ([crt0.S](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/07_soc_system_benchmarks/bsp/crt0.S)): Initializes stack pointer, zeros `.bss`, configures global pointer, calls `main()`, and writes termination code to `tohost`.
  - System Calls ([syscalls.c](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/07_soc_system_benchmarks/bsp/syscalls.c)): Implements `_write()` routing character streams directly to the UART FIFO.

---

## 2. Benchmark Suite Details

| Benchmark Target | Source Code | Algorithm & Purpose | Verification Condition | Typical CPI |
|------------------|-------------|---------------------|------------------------|-------------|
| `test_hello` | `src/hello/hello.c` | Basic runtime sanity check, UART console output, and sequential loop summation $\sum_{i=1}^{10} i$. | Final sum matches expected value 55; exit code `0x1`. | ~1.56 |
| `test_matmul` | `src/matmul/matmul.c` | Cache/RAM intensive $8 \times 8$ integer matrix multiplication with 3-level nested loops. | Golden element verification $C[0][0] == 37$; exit code `0x1`. | ~1.59 |
| `test_qsort` | `src/qsort/qsort.c` | Recursive in-place QuickSort sorting 64 pseudo-random integers. Exercises deep stack recursion and branch predictability. | Monotonic sort assertion $\forall i, A[i] \le A[i+1]$; exit code `0x1`. | ~1.73 |

---

## 3. How to Run

From this directory:

```bash
# Run all bare-metal C benchmarks
make test_all

# Run individual benchmarks
make test_hello
make test_matmul
make test_qsort

# Clean build and simulation artifacts
make clean
```

All benchmark runs invoke `run_c_bench.py` which:
1. Recompiles the SoC RTL in QuestaSim fresh (`--recompile-rtl`).
2. Compiles the C application with the GCC RV32 toolchain.
3. Converts the ELF into aligned memory hex vectors.
4. Executes simulation, streams real-time console characters, and monitors `tohost` completion.
