# =============================================================================
# 1TOPS RISC-V SoC Master Makefile
# =============================================================================

.PHONY: all help test test_all test_subsystems clean clean-all software testbench \
        test_01_core_modules test_02_pipeline_hazard test_03_cpu_core_arch \
        test_04_bus_fabric test_05_peripherals test_06_debugger test_07_benchmarks

all: help

help:
	@echo "=================================================================="
	@echo " 1TOPS RISC-V Pipelined SoC Master Makefile"
	@echo "=================================================================="
	@echo " Available Targets:"
	@echo "   make test             - Build software & run Verilator testbench"
	@echo "   make test_all         - Run all 7 complete subsystem verification suites"
	@echo "   make test_01_core_modules    - Subsystem 1: Core Datapath & ALU"
	@echo "   make test_02_pipeline_hazard - Subsystem 2: Microarchitectural Stress & SVA"
	@echo "   make test_03_cpu_core_arch   - Subsystem 3: CPU Architectural Compliance vs Spike"
	@echo "   make test_04_bus_fabric      - Subsystem 4: AMBA AHB/APB Bus Fabric (CRV)"
	@echo "   make test_05_peripherals     - Subsystem 5: Peripherals & Multiplier Accel"
	@echo "   make test_06_debugger        - Subsystem 6: Hardware Debugger & ADP Protocols"
	@echo "   make test_07_benchmarks      - Subsystem 7: Bare-Metal C SoC Benchmarks"
	@echo "   make clean            - Clean all build and simulation artifacts"
	@echo "=================================================================="

# 1. Default Verilator SoC Execution
test: software testbench
	@echo "======================================"
	@echo "        TESTING COMPLETE              "
	@echo "======================================"

software:
	$(MAKE) -C software clean
	$(MAKE) -C software

testbench: software
	$(MAKE) -C testbench clean
	$(MAKE) -C testbench run

# 2. Complete 7-Subsystem Verification Suites
test_all:
	@$(MAKE) -C final_tests test_all

test_subsystems: test_all

test_01_core_modules:
	@$(MAKE) -C final_tests test_01_core_modules

test_02_pipeline_hazard:
	@$(MAKE) -C final_tests test_02_pipeline_hazard

test_03_cpu_core_arch:
	@$(MAKE) -C final_tests test_03_cpu_core_arch

test_04_bus_fabric:
	@$(MAKE) -C final_tests test_04_bus_fabric

test_05_peripherals:
	@$(MAKE) -C final_tests test_05_peripherals

test_06_debugger:
	@$(MAKE) -C final_tests test_06_debugger

test_07_benchmarks:
	@$(MAKE) -C final_tests test_07_benchmarks

# 3. Clean
clean:
	$(MAKE) -C software clean
	$(MAKE) -C testbench clean
	@if [ -d final_tests ]; then $(MAKE) -C final_tests clean; fi
	@for d in standard_core_tests/*/; do \
		if [ -f "$${d}Makefile" ]; then $(MAKE) -C "$$d" clean; fi \
	done
	@rm -rf standard_core_tests/06_google_riscv_dv_torture/work standard_core_tests/06_google_riscv_dv_torture/build
	rm -rf schematics/vivado*.log schematics/vivado*.jou schematics/vivado*.str
	rm -rf schematics/*.backup.log schematics/*.backup.jou
	rm -rf schematics/.Xil
	rm -rf work output_files simulation riscv_pipelined.qws

clean-all: clean
	find . -type f -name '*~' -delete
	find . -type f -name '*.bak' -delete
	find . -type d -name '__pycache__' -exec rm -rf {} +
	find . -type f -name '.DS_Store' -delete
