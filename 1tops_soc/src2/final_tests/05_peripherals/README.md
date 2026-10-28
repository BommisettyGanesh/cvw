# Subsystem 05: Peripherals & Hardware Accelerators Verification

This subsystem contains dedicated self-checking verification tests for all SoC peripherals and hardware accelerators integrated via the AMBA AHB/APB interconnect.

---

## 1. Subsystem Architecture Overview

The peripheral subsystem connects to the CPU core via the Uncore subsystem and contains:
1. **AHB Hardware Multiplier Accelerator ([multiplier_ahb.v](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/main/multiplier_ahb.v))**:
   - Memory space: `0x3000_0000 - 0x30FF_FFFF` (Wally `EXT_MEM` space).
   - High-performance 32-bit hardware multiplication engine with memory-mapped operand registers:
     - `0x00`: Operand A (32-bit R/W)
     - `0x04`: Operand B (32-bit R/W)
     - `0x08`: Product Output (32-bit Read-Only: `Operand A * Operand B`)
     - `0x0C`: Testbench Console Character Output (Write-Only)
2. **GPIO Peripheral ([gpio_apb.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/uncore/gpio_apb.sv))**:
   - Base Address: `0x1006_0000`.
   - 32 general-purpose I/O pins with direction control (`GPIOEN`), output driver (`GPIOOUT`), input sampling (`GPIOIN`), and interrupt generation.
3. **16550 UART Peripheral ([uart_apb.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/uncore/uart_apb.sv))**:
   - Base Address: `0x1000_0000`.
   - Full 16550-compatible UART with Transmit/Receive Holding Registers (`RBR`/`THR`), Interrupt Enable Register (`IER`), FIFO Control (`FCR`), Line Control (`LCR`), and Line Status (`LSR`).
4. **CLINT (Core Local Interruptor) ([clint_apb.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/uncore/clint_apb.sv))**:
   - Base Address: `0x0200_0000`.
   - Implements RISC-V Privileged Architecture `mtime` (64-bit real-time counter) and `mtimecmp` (timer comparator for `MTIP` timer interrupt generation).
5. **PLIC (Platform-Level Interrupt Controller) ([plic_apb.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/uncore/plic_apb.sv))**:
   - Base Address: `0x0C00_0000`.
   - Routes, prioritizes, and arbitrates external peripheral interrupts (UART, GPIO, SPI) to the CPU core's `MEIP` external interrupt input with priority thresholds and claim/complete handshaking.

---

## 2. Test Suite Details

| Test Target | Target Peripheral | Test Source | Verification Scope |
|-------------|-------------------|-------------|--------------------|
| `test_multiplier` | AHB Multiplier Accelerator | `tb/tb_multiplier_ahb.sv` | Unit verification: Small positive, large values, zero/identity, signed 2's complement, and 50 constrained-random multiplications (165 assertion checks). |
| `test_gpio` | APB GPIO Subsystem | `src/WALLY-gpio-01.S` | Full SoC execution: Direction register toggling, pin mask generation, and readback against input stimulus `0xA5A55A5A`. |
| `test_uart` | APB 16550 UART | `src/WALLY-uart-01.S` | Full SoC execution: Divisor latch programming, loopback character transmit, FIFO status check, and receive buffer drain. |
| `test_clint` | APB CLINT Timer | `src/WALLY-clint-01.S` | Full SoC execution: `mtime` increments, timer interrupt arming via `mtimecmp`, and trap handler dispatch. |
| `test_plic` | APB PLIC Interrupts | `src/WALLY-plic-01.S` | Full SoC execution: Priority configuration, interrupt enablement, priority threshold masking, and atomic claim/complete cycle. |

---

## 3. How to Run

From this directory:

```bash
# Run all peripheral and accelerator tests
make test_all

# Run individual peripheral tests
make test_multiplier
make test_gpio
make test_uart
make test_clint
make test_plic

# Clean build and memory artifacts
make clean
```

All test runs compile libraries and assembly vectors fresh before simulation.
