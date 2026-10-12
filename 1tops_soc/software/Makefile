CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -mcmodel=medany -nostartfiles -nostdlib -T link.ld -O2

all: test_instr.mem test_data.mem factorial.bin

test.elf: crt0.S main.c
	$(CC) $(CFLAGS) $^ -o $@

test_instr.mem test_data.mem: test.elf
	$(OBJCOPY) -O binary $< test.bin
	python3 elf2mem.py test.bin test_instr.mem test_data.mem

factorial.elf: factorial.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

factorial.bin: factorial.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	cp -f $@ ../fpga/factorial.bin

clean:
	rm -f test.elf test.bin test_instr.mem test_data.mem factorial.elf factorial.bin ../fpga/factorial.bin
