# =============================================================================
# Makefile for EEMBC CoreMark 1.0 on Pure CPU Core
# =============================================================================

.PHONY: all run clean

all: run

run:
	@python3 run_coremark.py --iterations 1

clean:
	@rm -rf build work transcript vsim.wlf *.log
	@echo "[+] CoreMark test artifacts cleaned."
