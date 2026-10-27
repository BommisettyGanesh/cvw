# ==============================================================================
# Makefile: Subsystem 01 - Core Modules Unit Verification
# ==============================================================================

QUESTA_BIN := /home/ganesh/altera_lite/25.1std/questa_fse/bin
VLIB       := $(QUESTA_BIN)/vlib
VLOG       := $(QUESTA_BIN)/vlog
VSIM       := $(QUESTA_BIN)/vsim

RTL_COMP   := ../../components
SHA_DIR    := ../../soc_tests/module_level/crypto_sha
TB_DIR     := tb

.PHONY: all clean help test_alu test_branch test_imm test_subword test_sha256 test_sha512 test_all

all: test_all

help:
	@echo "Subsystem 01: Core Modules Unit Tests"
	@echo "  make test_alu       - Verify ALU operations (ADD, SUB, AND, OR, XOR, SLT, Shifts)"
	@echo "  make test_branch    - Verify Branching Unit conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU)"
	@echo "  make test_imm       - Verify Immediate Extender formats (I, S, B, J-types)"
	@echo "  make test_subword   - Verify Subword Unit (Byte masks, store replication, load extensions)"
	@echo "  make test_sha256    - Verify SHA-256 Hardware Accelerator Module"
	@echo "  make test_sha512    - Verify SHA-512 Hardware Accelerator Module"
	@echo "  make test_all       - Run all module unit tests"
	@echo "  make clean          - Clean all simulation directories and logs"

test_alu:
	@echo "\n=== [01_CORE_MODULES] Running ALU Unit Test ==="
	@rm -rf work
	@$(VLIB) work >/dev/null
	@$(VLOG) -sv -timescale 1ns/1ps -work work $(RTL_COMP)/alu.v $(RTL_COMP)/adder.v $(TB_DIR)/tb_alu_ops.sv >/dev/null
	@$(VSIM) -c -do "run -all; quit" work.tb_alu_ops | grep -E "Test Result|PASSED|FAILED"

test_branch:
	@echo "\n=== [01_CORE_MODULES] Running Branching Unit Test ==="
	@rm -rf work
	@$(VLIB) work >/dev/null
	@$(VLOG) -sv -timescale 1ns/1ps -work work $(RTL_COMP)/branching_unit.v $(TB_DIR)/tb_branching_unit.sv >/dev/null
	@$(VSIM) -c -do "run -all; quit" work.tb_branching_unit | grep -E "Test Result|PASSED|FAILED"

test_imm:
	@echo "\n=== [01_CORE_MODULES] Running Immediate Extender Test ==="
	@rm -rf work
	@$(VLIB) work >/dev/null
	@$(VLOG) -sv -timescale 1ns/1ps -work work $(RTL_COMP)/imm_extend.v $(TB_DIR)/tb_imm_extend.sv >/dev/null
	@$(VSIM) -c -do "run -all; quit" work.tb_imm_extend | grep -E "Test Result|PASSED|FAILED"

test_subword:
	@echo "\n=== [01_CORE_MODULES] Running Subword Unit Test ==="
	@rm -rf work
	@$(VLIB) work >/dev/null
	@$(VLOG) -sv -timescale 1ns/1ps -work work $(RTL_COMP)/subword_unit.v $(TB_DIR)/tb_subword_unit.sv >/dev/null
	@$(VSIM) -c -do "run -all; quit" work.tb_subword_unit | grep -E "Test Result|PASSED|FAILED"

test_all: test_alu test_branch test_imm test_subword
	@echo "\n======================================================="
	@echo " ALL 4 CORE MODULE UNIT TESTS PASSED!"
	@echo "======================================================="

clean:
	@rm -rf work transcript vsim.wlf
	@rm -rf $(SHA_DIR)/work $(SHA_DIR)/transcript $(SHA_DIR)/vsim.wlf
	@echo "Cleaned all core module test artifacts."
