CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -mcmodel=medany -nostartfiles -T link.ld -O2

all: test.mem

test.elf: crt0.S main.c
	$(CC) $(CFLAGS) $^ -o $@

test.mem: test.elf
	$(OBJCOPY) -O verilog $< $@

clean:
	rm -f test.elf test.mem
