# =============================================================================
# MASTER TEST RUNNER: Pipelined RISC-V SoC Verification Suite
# =============================================================================
# Executes clean, deterministic verification across all 7 architectural subsystems.
# Every test target recompiles RTL and testbenches fresh before simulation.
# =============================================================================

.PHONY: all help test_all clean \
        test_01_core_modules \
        test_02_pipeline_hazard \
        test_03_cpu_core_arch \
        test_04_bus_fabric \
        test_05_peripherals \
        test_06_debugger \
        test_07_benchmarks

all: test_all

help:
	@echo "=================================================================="
	@echo " RISC-V Pipelined SoC Subsystem Verification Suite"
	@echo "=================================================================="
	@echo " Subsystem Targets:"
	@echo "   make test_01_core_modules   - Unit tests (ALU, Branch, Extend, Subword, SHA)"
	@echo "   make test_02_pipeline_hazard- Microarchitectural stress (Hazards, Traps, SVA)"
	@echo "   make test_03_cpu_core_arch  - Architectural compliance (RV32I, Priv, Zicsr vs Spike)"
	@echo "   make test_04_bus_fabric     - AMBA AHB/APB bus fabric & arbiters (CRV)"
	@echo "   make test_05_peripherals    - Peripherals & Accelerator (GPIO, UART, CLINT, PLIC, Mult)"
	@echo "   make test_06_debugger       - Debugger features & ADP protocol (UART / FT1248)"
	@echo "   make test_07_benchmarks     - Full SoC bare-metal C applications (hello, matmul, qsort)"
	@echo ""
	@echo " Master Targets:"
	@echo "   make test_all               - Execute all 7 subsystem test suites end-to-end"
	@echo "   make clean                  - Clean all build and simulation artifacts"
	@echo "=================================================================="

test_01_core_modules:
	@echo "\n>>> [SUBSYSTEM 01/07] Running Core Modules Unit Tests..."
	@$(MAKE) -C 01_core_modules test_all

test_02_pipeline_hazard:
	@echo "\n>>> [SUBSYSTEM 02/07] Running Pipeline Hazard & Microarchitectural Stress..."
	@$(MAKE) -C 02_pipeline_hazard_stress test_all

test_03_cpu_core_arch:
	@echo "\n>>> [SUBSYSTEM 03/07] Running CPU Core Architectural Compliance..."
	@$(MAKE) -C 03_cpu_core_arch test_all

test_04_bus_fabric:
	@echo "\n>>> [SUBSYSTEM 04/07] Running Bus Interconnect & Fabric Verification..."
	@$(MAKE) -C 04_bus_fabric test_all

test_05_peripherals:
	@echo "\n>>> [SUBSYSTEM 05/07] Running Peripherals & Hardware Accelerators..."
	@$(MAKE) -C 05_peripherals test_all

test_06_debugger:
	@echo "\n>>> [SUBSYSTEM 06/07] Running Debugger Subsystem & Features..."
	@$(MAKE) -C 06_debugger_subsystem test_all

test_07_benchmarks:
	@echo "\n>>> [SUBSYSTEM 07/07] Running SoC Top-Level System & Bare-Metal C Benchmarks..."
	@$(MAKE) -C 07_soc_system_benchmarks test_all

test_all: test_01_core_modules \
          test_02_pipeline_hazard \
          test_03_cpu_core_arch \
          test_04_bus_fabric \
          test_05_peripherals \
          test_06_debugger \
          test_07_benchmarks
	@echo ""
	@echo "=================================================================="
	@echo " >>> ALL 7 SUBSYSTEM VERIFICATION SUITES PASSED SUCCESSFULLY! <<< "
	@echo "=================================================================="

clean:
	@$(MAKE) -C 01_core_modules clean
	@$(MAKE) -C 02_pipeline_hazard_stress clean
	@$(MAKE) -C 03_cpu_core_arch clean
	@$(MAKE) -C 04_bus_fabric clean
	@$(MAKE) -C 05_peripherals clean
	@$(MAKE) -C 06_debugger_subsystem clean
	@$(MAKE) -C 07_soc_system_benchmarks clean
	@echo "All subsystem artifacts cleaned."
