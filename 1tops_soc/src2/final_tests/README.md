# Pipelined RISC-V SoC: Comprehensive Subsystem Verification Suite (`final_tests/`)

This directory contains the complete, production-grade verification suite for the 5-stage pipelined RISC-V System-on-Chip (SoC) with AMBA AHB/APB interconnect, hardware accelerators, peripherals, and runtime debugger.

Every subsystem is organized into a dedicated, self-contained directory containing:
1. Complete self-checking testbenches and stimulus vectors.
2. An independent `Makefile` that compiles all RTL and testbenches fresh on every run (zero stale artifacts).
3. A detailed `README.md` explaining test theory, subsystem architecture, verification scope, and step-by-step execution commands.

---

## 1. Subsystem Directory Map

```
final_tests/
├── 01_core_modules/             # Subsystem 01: Core RTL Units (ALU, Branch, Extend, Subword, SHA)
│   ├── tb/                      # Self-checking SystemVerilog testbenches
│   ├── Makefile                 # Independent compiler and simulation runner
│   └── README.md                # Comprehensive documentation
│
├── 02_pipeline_hazard_stress/   # Subsystem 02: Microarchitectural Pipeline & Hazard Stress
│   ├── src/                     # Hand-crafted corner-case assembly routines
│   ├── assertions/              # Bound Formal SystemVerilog Assertions (SVA)
│   ├── testbench/               # Top-level stress testbench & monitors
│   ├── Makefile                 # Automated assembly compilation and simulation runner
│   └── README.md                # Comprehensive documentation
│
├── 03_cpu_core_arch/            # Subsystem 03: CPU Core Architectural Compliance (vs Spike ISS)
│   ├── Makefile                 # Compliance test runner across RV32I, Priv, Zicsr
│   └── README.md                # Architectural test documentation
│
├── 04_bus_fabric/               # Subsystem 04: AMBA AHB/APB Interconnect & Arbiters
│   ├── tb/                      # Constrained-Random Verification (CRV) testbenches
│   ├── assertions/              # Protocol checkers (AHB & APB)
│   ├── Makefile                 # Interconnect verification runner
│   └── README.md                # Bus arbitration and bridge documentation
│
├── 05_peripherals/              # Subsystem 05: Peripherals & Hardware Accelerators
│   ├── tb/                      # AHB Multiplier accelerator testbench
│   ├── soc_level/               # Assembly tests for GPIO, UART, CLINT, PLIC
│   ├── sim/                     # SoC simulation environment
│   ├── Makefile                 # Peripheral verification runner
│   └── README.md                # Peripheral memory map and test documentation
│
├── 06_debugger_subsystem/       # Subsystem 06: Hardware Debugger Subsystem & CPU Features
│   ├── tb/                      # Microarchitectural features & ADP protocol testbenches
│   ├── assertions/              # Pipeline invariant monitors
│   ├── Makefile                 # Debugger test runner
│   └── README.md                # ExternalStall, InstrRetired & ADP documentation
│
├── 07_soc_system_benchmarks/    # Subsystem 07: SoC Top-Level System & Bare-Metal C Benchmarks
│   ├── bsp/                     # Linker script, crt0.S startup, syscalls, UART driver
│   ├── src/                     # C applications: hello, matmul, qsort
│   ├── tb_c_bench.v             # Full SoC benchmark testbench
│   ├── run_c_bench.py           # Automated GCC compiler and QuestaSim execution driver
│   ├── Makefile                 # Benchmark runner
│   └── README.md                # Algorithm metrics, CPI, and benchmark documentation
│
├── Makefile                     # Master Test Runner (executes all 7 subsystems)
└── README.md                    # Master Verification Overview
```

---

## 2. Summary of Subsystems & Verification Coverage

| Subsystem | Folder | Target Modules | Verification Method | Tests Included |
|---|---|---|---|---|
| **01. Core Modules** | `01_core_modules/` | ALU, Branch Unit, Immediate Extender, Subword Unit, SHA-256, SHA-512 | Self-checking SV testbenches with exhaustive stimulus | `test_alu`, `test_branch`, `test_imm_extend`, `test_subword`, `test_sha256`, `test_sha512` |
| **02. Pipeline & Hazards** | `02_pipeline_hazard_stress/` | 5-stage CPU Pipeline, Hazard Unit, Forwarding Muxes | Stress assembly programs with formal SystemVerilog Assertions (SVA) | `hazard_forwarding`, `branch_collision`, `interrupt_trap`, `exception_trap`, `subword_access`, `apb_bus_stress` |
| **03. Architectural Compliance** | `03_cpu_core_arch/` | RV32I Base Integer, Privileged M-mode, Zicsr Extension | Lock-step architectural comparison against Spike Golden ISS | `test_alu_arch`, `test_branch_arch`, `test_memory_arch`, `test_priv_arch`, `test_zicsr_arch` |
| **04. Bus Interconnect** | `04_bus_fabric/` | 2-Master AHB Arbiter (`ahb_mux.sv`), AHB-to-APB Bridge (`ahbapbbridge.v`) | Constrained-Random Verification (CRV) with protocol assertions | `test_ahb_mux` (priority, contention, core halt), `test_apb_bridge` (setup, access, wait-states) |
| **05. Peripherals & Accelerators** | `05_peripherals/` | AHB Multiplier Accelerator, APB GPIO, 16550 UART, CLINT, PLIC | Directed unit testbenches + OpenHW CVW peripheral firmware | `test_multiplier`, `test_gpio`, `test_uart`, `test_clint`, `test_plic` |
| **06. Debugger Subsystem** | `06_debugger_subsystem/` | SoCDebug Top (`riscv_debugger_top.sv`), ADP Controller, Step Controller | Deterministic signal-level timing checks & ADP protocol testbench | `test_features` (`ExternalStall`, `InstrRetired`, `dbg_core_reset`), `test_adp_protocol` (UART/FT1248) |
| **07. System C Benchmarks** | `07_soc_system_benchmarks/` | Full SoC System (CPU, 2MB RAM, UART, CSR Performance Counters) | Bare-metal C execution with real-time UART streaming & `tohost` | `test_hello` (loop math), `test_matmul` (8x8 matrix), `test_qsort` (64-int quicksort) |

---

## 3. How to Run the Verification Suite

### Running the Complete Master Test Suite
To run all 7 subsystems end-to-end:
```bash
cd final_tests
make test_all
```

### Running Individual Subsystem Suites
You can run any subsystem independently from the master Makefile or from within each subdirectory:

```bash
# Subsystem 01: Core Modules Unit Tests
make test_01_core_modules
# OR
cd 01_core_modules && make test_all

# Subsystem 02: Pipeline Hazard & Stress Tests
make test_02_pipeline_hazard
# OR
cd 02_pipeline_hazard_stress && make test_all

# Subsystem 03: CPU Architectural Compliance Tests
make test_03_cpu_core_arch
# OR
cd 03_cpu_core_arch && make test_all

# Subsystem 04: Bus Fabric & Arbiter Tests
make test_04_bus_fabric
# OR
cd 04_bus_fabric && make test_all

# Subsystem 05: Peripherals & Hardware Accelerators
make test_05_peripherals
# OR
cd 05_peripherals && make test_all

# Subsystem 06: Debugger Subsystem & Features
make test_06_debugger
# OR
cd 06_debugger_subsystem && make test_all

# Subsystem 07: SoC Bare-Metal C Benchmarks
make test_07_benchmarks
# OR
cd 07_soc_system_benchmarks && make test_all
```

### Cleaning Artifacts
To wipe all compiled libraries, object files, logs, and memory dumps across all 7 subsystems:
```bash
make clean
```
