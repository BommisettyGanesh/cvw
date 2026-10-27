# =============================================================================
# Makefile for Subsystem 07: SoC Top-Level System & Bare-Metal C Benchmarks
# =============================================================================

PYTHON ?= python3

.PHONY: all test_all test_hello test_matmul test_qsort clean

all: test_all

test_hello:
	@echo "================================================================"
	@echo " Running Bare-Metal C Benchmark: Hello World & Loop Math        "
	@echo "================================================================"
	$(PYTHON) run_c_bench.py --test hello --recompile-rtl

test_matmul:
	@echo "================================================================"
	@echo " Running Bare-Metal C Benchmark: 8x8 Matrix Multiplication     "
	@echo "================================================================"
	$(PYTHON) run_c_bench.py --test matmul --recompile-rtl

test_qsort:
	@echo "================================================================"
	@echo " Running Bare-Metal C Benchmark: QuickSort (64 Integers)        "
	@echo "================================================================"
	$(PYTHON) run_c_bench.py --test qsort --recompile-rtl

test_all: test_hello test_matmul test_qsort
	@echo ""
	@echo "================================================================"
	@echo " ALL BARE-METAL C SYSTEM BENCHMARKS PASSED SUCCESSFULLY!        "
	@echo "================================================================"

clean:
	rm -rf work build transcript vsim.wlf
