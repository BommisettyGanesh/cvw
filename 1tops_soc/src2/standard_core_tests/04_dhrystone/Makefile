# =============================================================================
# Makefile for Dhrystone 2.1 on Pure CPU Core
# =============================================================================

.PHONY: all run clean

all: run

run:
	@python3 run_dhrystone.py --runs 100

clean:
	@rm -rf build work transcript vsim.wlf *.log
	@echo "[+] Dhrystone test artifacts cleaned."
