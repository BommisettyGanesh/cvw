# =============================================================================
# Makefile for Subsystem 05: Peripherals & Hardware Accelerators
# =============================================================================

ROOT_DIR := $(abspath ../..)
QUESTA_BIN ?= /home/ganesh/altera_lite/25.1std/questa_fse/bin

VLIB := $(QUESTA_BIN)/vlib
VLOG := $(QUESTA_BIN)/vlog
VSIM := $(QUESTA_BIN)/vsim

SOC_DIR := $(CURDIR)/soc_level
SIM_DIR := $(CURDIR)/sim

.PHONY: all test_all test_multiplier test_gpio test_uart test_clint test_plic clean

all: test_all

# Recompile the complete SoC fresh on every test run
compile_soc:
	@echo "--- Compiling SoC RTL and simulation testbench in QuestaSim ---"
	@rm -rf $(SIM_DIR)/work $(SIM_DIR)/transcript $(SIM_DIR)/vsim.wlf
	@$(VLIB) $(SIM_DIR)/work >/dev/null
	@$(VLOG) -sv -timescale 1ns/1ps -work $(SIM_DIR)/work \
		+incdir+$(ROOT_DIR)/main \
		+incdir+$(ROOT_DIR)/main/soc \
		+incdir+$(ROOT_DIR)/components \
		+incdir+$(ROOT_DIR)/uncore \
		+incdir+$(ROOT_DIR)/debugger \
		$(ROOT_DIR)/components/*.v \
		$(ROOT_DIR)/main/*.v \
		$(ROOT_DIR)/main/soc/*.v \
		$(ROOT_DIR)/uncore/*.sv \
		$(ROOT_DIR)/debugger/*.v \
		$(ROOT_DIR)/debugger/*.sv \
		$(SIM_DIR)/tb.sv >/dev/null

# 1. Hardware Multiplier Accelerator Test
test_multiplier:
	@echo "================================================================"
	@echo " Running Test: AHB Hardware Multiplier Accelerator             "
	@echo "================================================================"
	rm -rf work transcript vsim.wlf
	$(VLIB) work >/dev/null
	$(VLOG) -sv -work work $(ROOT_DIR)/main/soc/multiplier_ahb.v tb/tb_multiplier_ahb.sv >/dev/null
	$(VSIM) -c -do "run -all; quit -f" work.tb_multiplier_ahb

# 2. GPIO Peripheral Test
test_gpio: compile_soc
	@echo "================================================================"
	@echo " Running Test: WALLY-gpio-01 (GPIO Peripheral Verification)     "
	@echo "================================================================"
	@$(MAKE) -C $(SOC_DIR) prep_WALLY-gpio-01 >/dev/null
	@cp $(SOC_DIR)/test_instr.mem $(SIM_DIR)/ && cp $(SOC_DIR)/test_data.mem $(SIM_DIR)/
	@cd $(SIM_DIR) && $(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb | grep -E "Test Result|PASSED|FAILED|signature"

# 3. UART Peripheral Test
test_uart: compile_soc
	@echo "================================================================"
	@echo " Running Test: WALLY-uart-01 (16550 UART Peripheral)           "
	@echo "================================================================"
	@$(MAKE) -C $(SOC_DIR) prep_WALLY-uart-01 >/dev/null
	@cp $(SOC_DIR)/test_instr.mem $(SIM_DIR)/ && cp $(SOC_DIR)/test_data.mem $(SIM_DIR)/
	@cd $(SIM_DIR) && $(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb | grep -E "Test Result|PASSED|FAILED|signature"

# 4. CLINT Peripheral Test
test_clint: compile_soc
	@echo "================================================================"
	@echo " Running Test: WALLY-clint-01 (CLINT Core Local Interruptor)    "
	@echo "================================================================"
	@$(MAKE) -C $(SOC_DIR) prep_WALLY-clint-01 >/dev/null
	@cp $(SOC_DIR)/test_instr.mem $(SIM_DIR)/ && cp $(SOC_DIR)/test_data.mem $(SIM_DIR)/
	@cd $(SIM_DIR) && $(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb | grep -E "Test Result|PASSED|FAILED|signature"

# 5. PLIC Peripheral Test
test_plic: compile_soc
	@echo "================================================================"
	@echo " Running Test: WALLY-plic-01 (PLIC Platform-Level Interrupts)  "
	@echo "================================================================"
	@$(MAKE) -C $(SOC_DIR) prep_WALLY-plic-01 >/dev/null
	@cp $(SOC_DIR)/test_instr.mem $(SIM_DIR)/ && cp $(SOC_DIR)/test_data.mem $(SIM_DIR)/
	@cd $(SIM_DIR) && $(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb | grep -E "Test Result|PASSED|FAILED|signature"

test_all: test_multiplier test_gpio test_uart test_clint test_plic
	@echo ""
	@echo "================================================================"
	@echo " ALL PERIPHERAL & ACCELERATOR TESTS PASSED SUCCESSFULLY!        "
	@echo "================================================================"

clean:
	rm -rf work transcript vsim.wlf
	@$(MAKE) -C $(SOC_DIR) clean
	rm -rf $(SIM_DIR)/work $(SIM_DIR)/transcript $(SIM_DIR)/vsim.wlf $(SIM_DIR)/*.mem
