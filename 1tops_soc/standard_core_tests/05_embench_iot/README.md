# Embench-IoT Algorithmic Benchmark Suite (Pure CPU Core)

## 1. Overview & Industry Significance
**Embench™-IoT** is the modern, open-source embedded benchmark suite developed by the Free and Open Source Silicon (FOSS) community and leading academic institutions (University of Bristol, Embecosm). Designed to succeed aging proprietary benchmarks like EEMBC and Dhrystone, Embench focuses specifically on realistic, modern algorithmic workloads encountered in deeply embedded microcontrollers and IoT edge nodes.

Unlike synthetic benchmarks with tiny loop bodies that fit entirely in registers, Embench exercises realistic algorithmic patterns:
- Multi-dimensional array manipulations and matrix transformations
- Cryptographic hash functions with intense bitwise permutation trees
- Digital signal processing (FIR/IIR filter taps)
- Table-driven polynomial CRC checksum generation

---

## 2. Benchmark Kernels Included

| Kernel | Domain | Computational Characteristics | Golden Verification Method |
| :--- | :--- | :--- | :--- |
| **`crc32`** | Telecommunications & Networking | 32-bit ANSI X3.66 cyclic redundancy check using a 256-entry lookup table and pseudorandom data streams. | Golden checksum `11433 == r` |
| **`matmult-int`** | Linear Algebra & Numerical Computing | 20×20 integer matrix multiplication exercising nested loops, multidimensional array indexing, and heavy multiply-accumulate chains. | 20×20 bit-exact comparison against precomputed reference matrix |
| **`nettle-sha256`** | Security & Cryptography | SHA-256 cryptographic hash block compression from the GNU Nettle cryptographic library. | Bit-exact digest hash match |
| **`edn`** | Digital Signal Processing (DSP) | Extended Dot Product / Finite Impulse Response (FIR) signal filtering with integer coefficient arrays. | Signal vector convergence verification |

---

## 3. Pure CPU Core Test Architecture
This benchmark suite tests the **pure CPU core** in complete isolation from the SoC:
- **DUT**: Pure `riscv_cpu` (`main/riscv_cpu.v` + `components/*.v`)
- **Memory Subsystem**: Single-cycle synchronous `ahb_ram` (`main/ahb_ram.v`) mapped directly to AHB-Lite instruction and data buses.
- **Uncore Exclusions**: Zero APB bridge, zero UART, GPIO, PLIC, CLINT, or FT1248 debugger overhead.
- **Memory Layout**:
  - `0x8000_0000 - 0x8000_0FFF`: Reset boot stub (`.text.init` in `INIT` region)
  - `0x8000_1000`: Real-time ASCII character console port (monitored by testbench)
  - `0x8000_1004`: `tohost` benchmark completion mailbox (1 = PASS, 0 = FAIL)
  - `0x8000_2000 - 0x801F_FFFF`: Main program, constants, and data (`RAM` region)
  - `0x801F_F000`: Top of stack

---

## 4. Measured Performance Metrics on `riscv_cpu`

All 4 kernels execute and verify mathematical correctness with 100% pass rates:

| Benchmark Kernel | Kernel Cycles | Retired Instructions | Core CPI | Core IPC | Mathematical Result | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **`crc32`** | 50,281 | 38,995 | **1.28** | 0.77 | `11433` (Bit-exact match) | **PASS** |
| **`matmult-int`** | 1,138,260 | 652,489 | **1.74** | 0.57 | 400 matrix entries match | **PASS** |
| **`nettle-sha256`** | 11,076 | 9,594 | **1.15** | 0.86 | SHA-256 digest match | **PASS** |
| **`edn`** | 1,501,053 | 862,726 | **1.73** | 0.57 | Filter convergence match | **PASS** |

---

## 5. How to Run

### Run All Kernels
```bash
cd standard_core_tests/05_embench_iot
make all
```

### Run Individual Kernels
```bash
# Run CRC-32 (Fast, ~7s)
make test_crc32

# Run Nettle SHA-256 (Ultra-fast, ~2s)
make test_sha256

# Run 20x20 Matrix Multiplication (~1m 50s)
make test_matmult

# Run EDN Digital Filter (~2m 10s)
make test_edn
```

### Clean Build and Simulation Artifacts
```bash
make clean
```
