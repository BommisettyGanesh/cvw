VERILATOR = verilator
VFLAGS = -Wall -Wno-fatal --trace -cc --exe -f ../filelist.f --top-module tb
INC_DIRS = -I../src/wally -I../src/uncore -I../src/generic/mem -I../src/accelerator -I../config

all: sim

sim:
	cd .. && $(VERILATOR) -Wall -Wno-fatal --trace -cc --exe -f filelist.f --top-module tb -Isrc/wally -Isrc/uncore -Isrc/generic/mem -Isrc/accelerator -Iconfig -Mdir testbench/obj_dir $(CURDIR)/sim_main.cpp $(CURDIR)/tb.sv
	make -j -C obj_dir -f Vtb.mk Vtb

run: sim
	cp ../software/test_instr.mem .
	cp ../software/test_data.mem .
	./obj_dir/Vtb

clean:
	rm -rf obj_dir trace.vcd test_instr.mem test_data.mem sim_out.txt
