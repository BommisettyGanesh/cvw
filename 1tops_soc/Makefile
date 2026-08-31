.PHONY: all test clean software testbench

all: test

test: software testbench
	@echo "======================================"
	@echo "        TESTING COMPLETE              "
	@echo "======================================"

software:
	$(MAKE) -C software clean
	$(MAKE) -C software

testbench: software
	$(MAKE) -C testbench clean
	$(MAKE) -C testbench run

clean:
	$(MAKE) -C software clean
	$(MAKE) -C testbench clean
