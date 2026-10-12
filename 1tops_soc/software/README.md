# 1TOPS SoC Bare-Metal Software Environment

This directory contains bare-metal test programs, startup code, linker scripts, and utility tools for the **CORE-V Wally RISC-V SoC (`1tops_soc`)**.

The processor core implements a minimal **RV32I** instruction set (no M, A, F, D, C extensions). All multiplication and division operations in software must either use shift-and-add loops or offload directly to dedicated hardware accelerators at `0x3000_0000`.

---

## 1. Directory Files

| File | Description | Target |
| :--- | :--- | :--- |
| **`factorial.S`** | Pure RV32I bare-metal assembly calculating $n!$ using shift-and-add. | FPGA memory upload & core execution demo |
| **`main.c`** | C test program testing hardware multiplier accelerator and UART printing. | Verilator SoC simulation & verification |
| **`crt0.S`** | C runtime startup assembly (initializes stack pointer `sp` to top of Data RAM). | Runtime wrapper for `main.c` |
| **`link.ld`** | Linker script defining memory regions: Instruction RAM (`0x8000_0000`) and Data RAM (`0x8000_2000`). | GNU Linker |
| **`elf2mem.py`** | Converts binary images into `$readmemh` format text files for simulation. | Verilator testbench |
| **`Makefile`** | Builds all simulation memory files and FPGA binary images. | Build system |

---

## 2. Memory Layout

Defined in `link.ld`:

```text
+-----------------------+ 0x8000_0000 (Reset Vector)
|  Instruction RAM      |
|  .text (8 KB)         |
+-----------------------+ 0x8000_2000
|  Data RAM             |
|  .data / .sdata / .bss|
|  Heap                 |
|                       |
|  Stack (grows down)   |
+-----------------------+ 0x8000_4000 (Initial Stack Pointer)
```

---

## 3. How to Build

### Prerequisites
- GNU RISC-V toolchain (`riscv64-unknown-elf-gcc`, `riscv64-unknown-elf-objcopy`).
- Python 3.

### Build Commands
```bash
cd 1tops_soc/software

# Compile everything (simulation memories + factorial FPGA binary)
make all

# Compile only the factorial program (produces 76-byte factorial.bin)
make factorial.bin

# Clean build artifacts
make clean
```

---

## 4. Factorial Demo Program (`factorial.S`)

The factorial demo is written in pure RV32I instructions. It does not require any C runtime, standard library, or hardware multiplier:

1. **Input**: Reads $n$ from the 1st word of Data Memory: `0x8000_2000`.
2. **Algorithm**: Computes $n! = n \times (n-1) \times \dots \times 1$ using an inner shift-and-add unsigned multiplication routine (`mul_step`).
3. **Output**: Writes the 32-bit result to the 2nd word of Data Memory: `0x8000_2004`.
4. **Halt**: Loops indefinitely at `halt:` (`j halt`) to keep processor state frozen.

### Size
The assembled text section is exactly **76 bytes (`0x4C` bytes)**.

---

## 5. Loading and Running `factorial.bin` on FPGA via HTerm

Once the FPGA bitstream is running on the Basys 3 board, follow these steps to load and run the program:

1. **Connect HTerm**: 115200 Baud, 8 Data Bits, 1 Stop Bit, No Parity, No Flow Control.
2. **Enter ADP Mode**: Send `<ESC>` (`1B` in HEX mode) to receive prompt `]`.
3. **Halt Core**:
   ```text
   C 0202
   ```
4. **Clear Instruction RAM**:
   ```text
   A 80000000
   V 00000000
   F 200
   ```
5. **Set Input ($n = 5$)**:
   ```text
   A 80002000
   W 00000005
   W 00000000
   ```
6. **Upload `factorial.bin`**:
   ```text
   A 80000000
   U 4c
   ```
   In HTerm, click **Send File**, select `factorial.bin`, and send. The board will reply `U 0x0000004c` and prompt `]`.
7. **Restart & Run**:
   ```text
   C 0201
   C 0101
   C 0102
   ```
8. **Halt & Check Result**:
   ```text
   C 0202
   A 80002004
   R
   ```
   **Expected Response**: `R 0x00000078` ($120_{10} = 5!$).
