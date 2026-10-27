# =============================================================================
# Makefile for UC Berkeley riscv-tests on Pure CPU Core
# =============================================================================

.PHONY: all test_all test_alu test_branch test_memory test_hazard clean

all: test_all

test_all:
	@python3 run_berkeley_tests.py --group all

test_alu:
	@python3 run_berkeley_tests.py --group alu

test_branch:
	@python3 run_berkeley_tests.py --group branch

test_memory:
	@python3 run_berkeley_tests.py --group memory

test_hazard:
	@python3 run_berkeley_tests.py --group hazard

clean:
	@rm -rf build work transcript vsim.wlf *.log
	@echo "[+] UC Berkeley test artifacts cleaned."
