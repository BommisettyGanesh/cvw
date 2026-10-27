# =============================================================================
# Makefile for Standard Core Test 01: RISC-V International Architecture Tests
# =============================================================================

PYTHON ?= python3

.PHONY: all test_all test_alu test_branch test_memory test_priv test_zicsr clean

all: test_all

test_alu:
	$(PYTHON) run_core_arch_test.py --group alu

test_branch:
	$(PYTHON) run_core_arch_test.py --group branch

test_memory:
	$(PYTHON) run_core_arch_test.py --group memory

test_priv:
	$(PYTHON) run_core_arch_test.py --group priv

test_zicsr:
	$(PYTHON) run_core_arch_test.py --group zicsr

test_all:
	$(PYTHON) run_core_arch_test.py --group all

clean:
	rm -rf work build transcript vsim.wlf
