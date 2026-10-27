# ==============================================================================
# Makefile: Subsystem 02 - Pipeline Hazard & Microarchitectural Stress Verification
# ==============================================================================

QUESTA_BIN := /home/ganesh/altera_lite/25.1std/questa_fse/bin
VLIB       := $(QUESTA_BIN)/vlib
VLOG       := $(QUESTA_BIN)/vlog
VSIM       := $(QUESTA_BIN)/vsim

CC         := riscv64-unknown-elf-gcc
OBJCOPY    := riscv64-unknown-elf-objcopy
PYTHON     := python3

ROOT_DIR   := $(abspath ../..)
SRC_DIR    := $(CURDIR)/src
TB_DIR     := $(CURDIR)/testbench
ASSERT_DIR := $(CURDIR)/assertions
DBG_DIR    := $(ROOT_DIR)/debugger

CFLAGS     := -march=rv32i -mabi=ilp32 -static -mcmodel=medany -nostdlib -nostartfiles -g -T $(SRC_DIR)/link.ld

.PHONY: all help clean \
        test_hazards test_branch_collision test_interrupts \
        test_exceptions test_subwords test_apb_stress test_all

all: test_all

help:
	@echo "Subsystem 02: Pipeline Hazard & Microarchitectural Stress Suite"
	@echo "  make test_hazards          - RAW hazard forwarding & load-use stall tests"
	@echo "  make test_branch_collision  - Branch misprediction & pipeline shadow flush tests"
	@echo "  make test_interrupts       - CLINT timer interrupts, CSRs & mret return tests"
	@echo "  make test_exceptions       - ecall, ebreak, and illegal instruction trap tests"
	@echo "  make test_subwords         - Byte strobes (HWSTRB) & memory alignment tests"
	@echo "  make test_apb_stress       - Rapid back-to-back APB bus transfers"
	@echo "  make test_all              - Run all 6 pipeline stress tests"
	@echo "  make clean                 - Remove all build and simulation artifacts"

# Target to compile an assembly test and run in QuestaSim
define run_stress_test
	@echo "\n=== [02_PIPELINE_STRESS] Running $(1) ==="
	@mkdir -p $(SRC_DIR)/build $(TB_DIR)/work
	@$(CC) $(CFLAGS) $(SRC_DIR)/$(1).S -o $(SRC_DIR)/build/$(1).elf
	@$(OBJCOPY) -O binary $(SRC_DIR)/build/$(1).elf $(SRC_DIR)/build/$(1).bin
	@$(PYTHON) $(SRC_DIR)/elf2mem.py $(SRC_DIR)/build/$(1).bin $(TB_DIR)/test_instr.mem $(TB_DIR)/test_data.mem 0x8000
	@cd $(TB_DIR) && rm -rf work && $(VLIB) work >/dev/null && \
	 $(VLOG) -sv -timescale 1ns/1ps -work work \
		+incdir+$(ROOT_DIR)/main +incdir+$(ROOT_DIR)/main/soc +incdir+$(ROOT_DIR)/components +incdir+$(ROOT_DIR)/uncore +incdir+$(DBG_DIR) \
		$(ROOT_DIR)/components/*.v $(ROOT_DIR)/main/*.v $(ROOT_DIR)/main/soc/*.v $(ROOT_DIR)/uncore/*.sv \
		$(DBG_DIR)/*.v $(DBG_DIR)/*.sv \
		$(ASSERT_DIR)/*.sv $(TB_DIR)/tb_pipeline_stress.sv >/dev/null && \
	 $(VSIM) -c -voptargs="+acc" -assertdebug -do "run -all; quit" work.tb_signal_level | grep -E "Result:|PASSED|FAILED"
endef

test_hazards:
	$(call run_stress_test,hazard_forwarding_stress)

test_branch_collision:
	$(call run_stress_test,branch_collision_stress)

test_interrupts:
	$(call run_stress_test,interrupt_trap_stress)

test_exceptions:
	$(call run_stress_test,exception_trap_stress)

test_subwords:
	$(call run_stress_test,subword_access_stress)

test_apb_stress:
	$(call run_stress_test,apb_bus_stress)

test_all: test_hazards test_branch_collision test_interrupts test_exceptions test_subwords test_apb_stress
	@echo "\n======================================================="
	@echo " ALL 6 PIPELINE HAZARD STRESS TESTS PASSED!"
	@echo "======================================================="

clean:
	@rm -rf $(SRC_DIR)/build $(TB_DIR)/work $(TB_DIR)/transcript $(TB_DIR)/vsim.wlf $(TB_DIR)/*.mem
	@echo "Cleaned all pipeline stress test artifacts."
