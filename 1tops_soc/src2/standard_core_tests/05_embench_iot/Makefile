# ==============================================================================
# Embench-IoT Algorithmic Benchmark Suite Makefile (Pure CPU Core)
# ==============================================================================

PYTHON ?= python3

.PHONY: all test_all test_crc32 test_matmult test_sha256 test_edn clean help

all: test_all

test_all:
	@echo "=================================================================="
	@echo " Running Complete Embench-IoT Algorithmic Suite on Pure Core..."
	@echo "=================================================================="
	$(PYTHON) run_embench.py --kernel all

test_crc32:
	$(PYTHON) run_embench.py --kernel crc32

test_matmult:
	$(PYTHON) run_embench.py --kernel matmult-int

test_sha256:
	$(PYTHON) run_embench.py --kernel nettle-sha256

test_edn:
	$(PYTHON) run_embench.py --kernel edn

clean:
	rm -rf build work transcript vsim.wlf *.log

help:
	@echo "Targets:"
	@echo "  make all / make test_all - Run all 4 Embench kernels"
	@echo "  make test_crc32          - Run CRC-32 ANSI checksum kernel"
	@echo "  make test_matmult        - Run 20x20 Integer Matrix Multiply kernel"
	@echo "  make test_sha256         - Run Nettle SHA-256 cryptographic hash kernel"
	@echo "  make test_edn            - Run EDN finite impulse response filter kernel"
	@echo "  make clean               - Clean all compilation and simulation artifacts"
