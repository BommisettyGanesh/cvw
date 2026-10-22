RISCV_PREFIX ?= $(shell which riscv64-unknown-elf-gcc >/dev/null 2>&1 && echo riscv64-unknown-elf- || (which riscv-none-elf-gcc >/dev/null 2>&1 && echo riscv-none-elf- || echo riscv64-unknown-elf-))
CC = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -mcmodel=medany -nostartfiles -nostdlib -T link.ld -O2

all: test_instr.mem test_data.mem factorial.bin trap_test.bin profile_accel.bin spi_test.bin step_test.bin

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

step_test.elf: step_test.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

step_test.bin: step_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	cp -f $@ ../fpga/step_test.bin

trap_test.elf: trap_test.S
	$(CC) -march=rv32i_zicsr -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

trap_test.bin: trap_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	cp -f $@ ../fpga/trap_test.bin

profile_accel.elf: profile_accel.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

profile_accel.bin: profile_accel.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	cp -f $@ ../fpga/profile_accel.bin

spi_test.elf: spi_test.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

spi_test.bin: spi_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	cp -f $@ ../fpga/spi_test.bin

clean:
	rm -f test.elf test.bin test_instr.mem test_data.mem factorial.elf factorial.bin step_test.elf step_test.bin trap_test.elf trap_test.bin profile_accel.elf profile_accel.bin spi_test.elf spi_test.bin ../fpga/factorial.bin ../fpga/step_test.bin ../fpga/trap_test.bin ../fpga/profile_accel.bin ../fpga/spi_test.bin
