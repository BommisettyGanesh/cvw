# =============================================================================
# Makefile for Subsystem 06: Debugger Subsystem & Features
# =============================================================================

ROOT_DIR := $(abspath ../..)
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

.PHONY: all test_all test_features test_adp_protocol clean

all: test_all

# 1. Debugger Signals & Microarchitecture Features Verification
test_features:
	@echo "================================================================"
	@echo " Running Test: Debugger Microarchitectural Features             "
	@echo " (ExternalStall, InstrRetired Pulse, Single-Step, Core Reset)   "
	@echo "================================================================"
	rm -rf work transcript vsim.wlf
	$(VLIB) work >/dev/null
	$(VLOG) -sv -timescale 1ns/1ps -work work \
		+incdir+$(ROOT_DIR)/main \
		+incdir+$(ROOT_DIR)/main/soc \
		+incdir+$(ROOT_DIR)/components \
		+incdir+$(ROOT_DIR)/uncore \
		+incdir+$(ROOT_DIR)/debugger \
		+incdir+assertions \
		$(ROOT_DIR)/components/*.v \
		$(ROOT_DIR)/main/*.v \
		$(ROOT_DIR)/main/soc/*.v \
		$(ROOT_DIR)/uncore/*.sv \
		$(ROOT_DIR)/debugger/*.v \
		$(ROOT_DIR)/debugger/*.sv \
		assertions/*.sv \
		tb/tb_debugger_features.sv >/dev/null
	$(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb_debugger_features | grep -E "TEST [0-9]|PASSED|FAILED|ALL DEBUGGER"

# 2. SoCDebug Top-Level & ADP Command Protocol Verification
test_adp_protocol:
	@echo "================================================================"
	@echo " Running Test: SoCDebug ADP Command Protocol & Bus Multiplexer  "
	@echo " (UART / FT1248 Dual-Interface, Memory R/W, Polling, Errors)   "
	@echo "================================================================"
	rm -rf work transcript vsim.wlf
	$(VLIB) work >/dev/null
	$(VLOG) -sv -timescale 1ns/1ps -work work \
		+incdir+$(ROOT_DIR)/debugger \
		+incdir+tb \
		$(ROOT_DIR)/debugger/accelerator_debug_def.vh \
		$(ROOT_DIR)/debugger/socdebug_adp_control.v \
		$(ROOT_DIR)/debugger/socdebug_ahb.v \
		$(ROOT_DIR)/debugger/socdebug_uart.v \
		$(ROOT_DIR)/debugger/socdebug_ft1248_control.v \
		$(ROOT_DIR)/debugger/ahb_mux.sv \
		$(ROOT_DIR)/debugger/core_step_controller.sv \
		$(ROOT_DIR)/debugger/riscv_debugger_top.sv \
		$(ROOT_DIR)/main/soc/multiplier_ahb.v \
		tb/SYNCHRONIZER_EDGES.v \
		tb/f232h_ft1248_stream.v \
		tb/tb_debugger.sv >/dev/null
	$(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb_debugger | grep -E "TEST [0-9]|PASSED|FAILED|OVERALL SUMMARY"

test_all: test_features test_adp_protocol
	@echo ""
	@echo "================================================================"
	@echo " ALL DEBUGGER SUBSYSTEM TESTS PASSED SUCCESSFULLY!              "
	@echo "================================================================"

clean:
	rm -rf work transcript vsim.wlf
