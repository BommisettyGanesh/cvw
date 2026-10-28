# ==============================================================================
# Makefile: OpenHW CVW SoC Peripheral Test Suite (RV32)
# Reference: openhwgroup/cvw/tests/periph/Makefile
# ==============================================================================

CC      := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
PYTHON  := python3

CFLAGS  := -march=rv32i -mabi=ilp32 -static -mcmodel=medany -nostdlib -nostartfiles -g -T link.ld -I .

SRCS    := $(wildcard src/*.S)
TESTS   := $(notdir $(basename $(SRCS)))
ELFS    := $(addprefix build/,$(addsuffix .elf,$(TESTS)))
BINS    := $(addprefix build/,$(addsuffix .bin,$(TESTS)))
DUMPS   := $(addprefix build/,$(addsuffix .objdump,$(TESTS)))

.PHONY: all clean $(TESTS)

all: $(ELFS) $(BINS) $(DUMPS)

build:
	mkdir -p build

build/%.elf: src/%.S link.ld WALLY-env.h WALLY-TEST-LIB.h | build
	$(CC) $(CFLAGS) -o $@ $<

build/%.bin: build/%.elf
	$(OBJCOPY) -O binary $< $@

build/%.objdump: build/%.elf
	$(OBJDUMP) -d -S $< > $@

# Target to prepare a specific test for memory preload into tb.sv
prep_%: build/%.bin
	$(PYTHON) elf2mem.py $< test_instr.mem test_data.mem

clean:
	rm -rf build test_instr.mem test_data.mem
