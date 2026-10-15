# Advanced Peripheral Verification Guide via Hardware Debugger

This guide outlines advanced, systematic methods to verify every memory-mapped peripheral on the **CORE-V Wally 1TOPS SoC** using the integrated **Dual-Protocol Hardware Debugger (ADP)** over **HTerm** (or the Python CLI `sw/dbg_cli.py`).

Because the on-chip debugger is an independent **AHB-Lite Bus Master**, you have two powerful testing paradigms:
1. **Zero-Instruction Direct MMIO Probing (Peeking & Poking)**: Driving peripheral state machines, FIFOs, and internal loopbacks directly from the serial terminal while the CPU core is halted—*without compiling or running any RISC-V code*.
2. **Debugger-Coordinated Stimulus Injection & Profiling**: Running small, targeted RV32I micro-programs while using the debugger as an asynchronous event injector (e.g. triggering interrupts, polling hardware status, measuring clock latency).

---

## Table of Contents
1. [Physical Memory & Peripheral Register Map](#1-physical-memory--peripheral-register-map)
2. [ADP Debugger Command Cheat Sheet](#2-adp-debugger-command-cheat-sheet)
3. [Method 1: 16550 UART Internal Hardware Loopback & Scratchpad (Zero-CPU)](#method-1-16550-uart-internal-hardware-loopback--scratchpad-zero-cpu)
4. [Method 2: CLINT Real-Time Clock & 64-Bit Carry Propagation (Zero-CPU)](#method-2-clint-real-time-clock--64-bit-carry-propagation-zero-cpu)
5. [Method 3: Live Software Interrupt Injection & Trap Handling (`MSIP`)](#method-3-live-software-interrupt-injection--trap-handling-msip)
6. [Method 4: GPIO Output Polarity Inversion & Edge Flag Verification](#method-4-gpio-output-polarity-inversion--edge-flag-verification)
7. [Method 5: SPI FIFO Backpressure & Watermark Threshold Verification](#method-5-spi-fifo-backpressure--watermark-threshold-verification)
8. [Method 6: Non-Intrusive Hardware Execution Latency Profiling](#method-6-non-intrusive-hardware-execution-latency-profiling)
9. [Quick-Reference Summary Table](#9-quick-reference-summary-table)

---

## 1. Physical Memory & Peripheral Register Map

| Peripheral / Space | Base Address | Range / Size | Purpose | Source Reference |
| :--- | :--- | :--- | :--- | :--- |
| **Boot ROM** | `0x0000_1000` | 4 KB | Reset execution / bootloader | [`src/uncore/rom_ahb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/rom_ahb.sv) |
| **CLINT** | `0x0200_0000` | 64 KB | Software interrupts (`msip`), Timer (`mtime`, `mtimecmp`) | [`src/uncore/clint_apb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/clint_apb.sv) |
| **PLIC** | `0x0C00_0000` | 64 MB | Platform-Level Interrupt Controller | [`src/uncore/plic_apb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/plic_apb.sv) |
| **16550 UART** | `0x1000_0000` | 8 Bytes | TI PC16550D UART with FIFOs & Loopback | [`src/uncore/uart_apb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/uart_apb.sv) |
| **SPI Controller** | `0x1004_0000` | 4 KB | SiFive FU540-compatible SPI master | [`src/uncore/spi_apb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/spi_apb.sv) |
| **GPIO** | `0x1006_0000` | 256 Bytes | 32-bit GPIO with XOR inversion & edge detection | [`src/uncore/gpio_apb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/gpio_apb.sv) |
| **1TOPS Accelerator** | `0x3000_0000` | 16 MB | Neural Network Multiplier / Matrix Engine | [`src/accelerator/`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/accelerator/) |
| **Instruction RAM (IRAM)** | `0x8000_0000` | 8 KB | CPU code execution space (Reset Vector) | [`src/uncore/ram_ahb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/ram_ahb.sv) |
| **Data RAM (DRAM)** | `0x8000_2000` | 8 KB | Scratchpad variables, stack, I/O mailboxes | [`src/uncore/ram_ahb.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/src/uncore/ram_ahb.sv) |

---

## 2. ADP Debugger Command Cheat Sheet

In HTerm (115200 Baud, 8-N-1, Send on Enter = `CR`):

| Command | Syntax | Description | Example |
| :--- | :--- | :--- | :--- |
| **Halt CPU** | `C 0202` | Freezes CPU pipeline stages in place without modifying registers | `C 0202` (LED 0 turns ON) |
| **Resume CPU** | `C 0201` | Resumes core execution from current PC | `C 0201` (LED 0 turns OFF) |
| **Reset CPU** | `C 0101` $\rightarrow$ `C 0102` | Asserts then deasserts core CPU reset | `C 0101` then `C 0102` |
| **Set Address** | `A <hex_addr>` | Sets internal 32-bit AHB bus address pointer | `A 10000000` |
| **Write Word** | `W <hex_val>` | Writes 32-bit word to current address, auto-increments address | `W 000000A5` |
| **Read Word** | `R` | Reads 32-bit word from current address | `R` $\rightarrow$ replies `R 0x...` |
| **Fill Memory**| `V <val>` then `F <cnt>`| Fills `<cnt>` words with value `<val>` | `V 00000000` then `F 200` |
| **Upload Binary**| `U <byte_count>` | Streams `<byte_count>` raw bytes into memory | `U 4c` |

---

## Method 1: 16550 UART Internal Hardware Loopback & Scratchpad (Zero-CPU)

### Principle
The integrated 16550 UART (`uartPC16550D.sv`) provides an internal **Loopback Diagnostic Mode** triggered by Bit 4 of the Modem Control Register (`MCR[4] = 1`). When active:
- Transmit output is internally connected directly to the receive input.
- External UART pins are disconnected.
- Output control signals (`RTS`, `DTR`, `OUT1`, `OUT2`) are internally looped to input control signals (`CTS`, `DSR`, `RI`, `DCD`).
- You can write a byte into the transmitter, watch the status register flag change, and read the byte out of the receiver—**all directly from HTerm without external wiring**.

### Register Offsets (Base: `0x1000_0000`)
- `0x1000_0000` (`+0`): Receiver Buffer (`RBR`, read) / Transmitter Holding Register (`THR`, write)
- `0x1000_0001` (`+1`): Interrupt Enable Register (`IER`)
- `0x1000_0002` (`+2`): FIFO Control Register (`FCR`, write)
- `0x1000_0003` (`+3`): Line Control Register (`LCR`, bit 7 = `DLAB`)
- `0x1000_0004` (`+4`): Modem Control Register (`MCR`, bit 4 = `LOOPBACK`)
- `0x1000_0005` (`+5`): Line Status Register (`LSR`, bit 0 = `DR` Data Ready, bit 5 = `THRE` Transmitter Empty)
- `0x1000_0007` (`+7`): Scratchpad Register (`SCR`)

---

### Step-by-Step HTerm Procedure

#### Part A: Bus Verification via Scratchpad Register (`SCR`)
The scratchpad register retains any 8-bit value written to it and has no effect on UART operations.
1. **Halt CPU**:
   ```text
   C 0202
   ```
2. **Write alternating bit pattern `0x55`**:
   ```text
   A 10000007
   W 00000055
   ```
3. **Read back**:
   ```text
   A 10000007
   R
   ```
   *Expected Response*: `R 0x00000055` (or replicated byte `0x55555555`).
4. **Write complementary bit pattern `0xAA`**:
   ```text
   A 10000007
   W 000000AA
   ```
5. **Read back**:
   ```text
   A 10000007
   R
   ```
   *Expected Response*: `R 0x000000AA`.

> [!NOTE]
> If Part A succeeds, you have verified the APB bridge, peripheral clocking, and subword write strobes (`HWSTRB`) to the UART block.

#### Part B: Loopback Data Transmission & Reception
1. **Enable Internal Loopback Mode** (`MCR[4] = 1`):
   ```text
   A 10000004
   W 00000010
   ```
2. **Verify Line Status Register (`LSR`) Initial State**:
   ```text
   A 10000005
   R
   ```
   *Expected*: Bit 0 (`DR` - Data Ready) is `0`. Bit 5 (`THRE` - Transmitter Holding Register Empty) is `1` (e.g. `0x00000060`).
3. **Transmit Test Character `0xA5` via `THR`**:
   ```text
   A 10000000
   W 000000A5
   ```
4. **Check Line Status Register (`LSR`)**:
   ```text
   A 10000005
   R
   ```
   *Expected*: Bit 0 is now `1` (`0x00000061` or `0x00000001`), confirming character received and sitting in FIFO.
5. **Read Received Character from `RBR`**:
   ```text
   A 10000000
   R
   ```
   *Expected Response*: `R 0x000000A5`.
6. **Confirm `LSR` Cleared**:
   ```text
   A 10000005
   R
   ```
   *Expected*: Bit 0 returned to `0` because reading `RBR` pops the FIFO.

---

## Method 2: CLINT Real-Time Clock & 64-Bit Carry Propagation (Zero-CPU)

### Principle
The Core Local Interruptor (`clint_apb.sv`) implements the RISC-V privileged specification `mtime` and `mtimecmp` registers:
- `mtime` ticks autonomously from the internal timebase/system clock.
- When `mtime >= mtimecmp`, the hardware timer interrupt line `MTimerInt` asserts to the CPU core.
- You can verify timebase rate, 64-bit carry propagation, and timer interrupt assertion directly from HTerm without code execution.

### Register Offsets (Base: `0x0200_0000`)
- `0x0200_0000`: `MSIP` (Machine Software Interrupt Pending, bit 0)
- `0x0200_4000`: `MTIMECMP` Lower 32 bits
- `0x0200_4004`: `MTIMECMP` Upper 32 bits
- `0x0200_BFF8`: `MTIME` Lower 32 bits
- `0x0200_BFFC`: `MTIME` Upper 32 bits

---

### Step-by-Step HTerm Procedure

#### Part A: Differential Rate Check (Proving the Clock is Running)
1. **Halt CPU**:
   ```text
   C 0202
   ```
2. **Read initial `mtime`**:
   ```text
   A 0200bff8
   R
   ```
   *(Record value $T_1$, e.g. `0x0024A100`).*
3. **Wait ~2 to 3 seconds**, then issue `R` again:
   ```text
   R
   ```
   *(Record value $T_2$, e.g. `0x061D8A40`).*
4. **Calculate rate**:
   $$\Delta T = T_2 - T_1$$
   Dividing $\Delta T$ by elapsed real time will match your MMCM clock frequency ($50\text{ MHz}$ or configured prescaler rate).

#### Part B: 64-Bit Rollover & Carry Propagation Test
Peripherals often suffer bugs when counter lower words roll over from `0xFFFF_FFFF` to `0x0000_0000`. Test this directly:
1. **Set `mtime` upper word to zero**:
   ```text
   A 0200bffc
   W 00000000
   ```
2. **Set `mtime` lower word 32 ticks before rollover**:
   ```text
   A 0200bff8
   W ffffffe0
   ```
3. **Wait 1 second**, then read upper word:
   ```text
   A 0200bffc
   R
   ```
   *Expected Response*: `R 0x00000001` (confirming that the carry bit propagated smoothly into the high register).

---

## Method 3: Live Software Interrupt Injection & Trap Handling (`MSIP`)

### Principle
Testing interrupt logic normally requires waiting for external pins. However, writing `1` to `CLINT_MSIP` (`0x0200_0000`) directly asserts the core's **Machine Software Interrupt line (`MSwInt`)**.

By placing the core in an idle `wfi` loop, you can inject an interrupt on-demand from HTerm and verify that:
1. The CPU branches to `mtvec`.
2. The trap handler executes and writes a token to DMem (`0x8000_2010`).
3. The core cleans up and returns via `mret`.

---

### Assembly Test Program: `trap_test.S`

Save the following assembly program as `../software/trap_test.S`:

```assembly
# trap_test.S - Live Software Interrupt Trap Verification
.section .text
.globl _start

_start:
    # 1. Initialize trap vector to handle_trap (Direct Mode)
    la    t0, handle_trap
    csrw  mtvec, t0

    # 2. Clear Mailbox in Data RAM (0x80002010 = 0)
    lui   s0, 0x80002
    sw    zero, 0x010(s0)

    # 3. Enable Machine Software Interrupts (mie.MSIE = bit 3)
    li    t1, 0x08
    csrs  mie, t1

    # 4. Enable Global Interrupts (mstatus.MIE = bit 3)
    csrsi mstatus, 0x08

wait_loop:
    # 5. Wait For Interrupt (or tight loop if WFI is NOP)
    wfi
    j     wait_loop

# -------------------------------------------------------------
# Trap Handler
# -------------------------------------------------------------
.align 4
handle_trap:
    # Read mcause to confirm it is Machine Software Interrupt (cause = 3)
    csrr  t2, mcause
    li    t3, 3
    bne   t2, t3, trap_exit

    # Increment Mailbox at 0x80002010 (indicates handler executed)
    lw    t4, 0x010(s0)
    addi  t4, t4, 1
    sw    t4, 0x010(s0)

    # Clear MSIP in CLINT (Address 0x02000000 = 0) to acknowledge interrupt
    lui   t5, 0x02000
    sw    zero, 0x000(t5)

trap_exit:
    mret
```

### Build & Deploy Walkthrough

1. **Compile & Extract Binary**:
   ```bash
   cd ../software
   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld trap_test.S -o trap_test.elf
   riscv-none-elf-objcopy -O binary --only-section=.text trap_test.elf trap_test.bin
   cp trap_test.bin ../fpga/
   ```
2. **Check Binary Size**:
   ```bash
   python3 -c "import os; s = os.path.getsize('trap_test.bin'); print(f'Size: {s} bytes (hex: 0x{s:x})')"
   ```
   *(Assume size is `0x58` bytes).*

3. **In HTerm**:
   ```text
   C 0202              # Halt CPU
   A 80000000          # Point to IRAM
   V 00000000          # Zero out IRAM
   F 200
   A 80000000
   U 58                # Send File -> trap_test.bin
   C 0201              # Resume CPU
   C 0101              # Reset CPU
   C 0102
   ```
   *(Core is now actively waiting in `wait_loop`).*

4. **Inject Interrupt Live from HTerm**:
   ```text
   A 02000000
   W 00000001
   ```
   *(Asserts `MSIP` $\rightarrow$ Core immediately enters `handle_trap`, increments mailbox, clears `MSIP`, and returns).*

5. **Verify Execution**:
   ```text
   C 0202              # Halt CPU
   A 80002010          # Check DMem mailbox
   R
   ```
   *Expected Response*: `R 0x00000001`!
   
6. **Repeat Test**:
   Write `W 00000001` to `0x02000000` again, resume core, halt, and read `0x80002010`. The value will increment to `R 0x00000002`.

---

## Method 4: GPIO Output Polarity Inversion & Edge Flag Verification

### Principle
The GPIO controller (`gpio_apb.sv`) implements SiFive FE310-compatible features including:
- Dynamic output polarity inversion (`GPIO_OUT_XOR`).
- Edge and level interrupt status registers (`GPIO_RISE_IP`, `GPIO_FALL_IP`, `GPIO_HIGH_IP`, `GPIO_LOW_IP`).

You can verify the GPIO internal inversion and edge capture logic entirely over HTerm.

### Register Offsets (Base: `0x1006_0000`)
- `0x1006_0000` (`+0x00`): `GPIO_INPUT_VAL` (Read pin state)
- `0x1006_0004` (`+0x04`): `GPIO_INPUT_EN`
- `0x1006_0008` (`+0x08`): `GPIO_OUTPUT_EN`
- `0x1006_000C` (`+0x0C`): `GPIO_OUTPUT_VAL`
- `0x1006_0018` (`+0x18`): `GPIO_RISE_IE` (Rise Interrupt Enable)
- `0x1006_001C` (`+0x1C`): `GPIO_RISE_IP` (Rise Interrupt Pending - write 1 to clear)
- `0x1006_0040` (`+0x40`): `GPIO_OUT_XOR` (Output Polarity Inversion)

---

### Step-by-Step HTerm Procedure

1. **Halt CPU**:
   ```text
   C 0202
   ```
2. **Enable Outputs on lower 8 pins**:
   ```text
   A 10060008
   W 000000ff
   ```
3. **Write test pattern `0xAA` to `GPIO_OUTPUT_VAL`**:
   ```text
   A 1006000c
   W 000000aa
   ```
4. **Read back `GPIO_OUTPUT_VAL`**:
   ```text
   A 1006000c
   R
   ```
   *Expected*: `R 0x000000AA`.
5. **Invert Polarity with `GPIO_OUT_XOR`**:
   ```text
   A 10060040
   W 000000ff
   ```
   *(Internally XORs the output value with `0xFF`: `0xAA ^ 0xFF = 0x55`).*
6. **Verify Input Loopback (if `P.GPIO_LOOPBACK_TEST` is configured)**:
   ```text
   A 10060004        # Enable inputs
   W 000000ff
   A 10060000        # Read GPIO_INPUT_VAL
   R
   ```
   *Expected*: Returns the inverted output value (`0x00000055`).

---

## Method 5: SPI FIFO Backpressure & Watermark Threshold Verification

### Principle
The SPI controller (`spi_apb.sv`) features synchronous 8-byte transmit and receive FIFOs with watermark threshold interrupt logic:
- When writing to `SPI_TXDATA` (`0x1004_0048`), Bit 31 is the `TX FIFO FULL` status flag.
- When the FIFO fills completely, Bit 31 asserts (`1`).
- `SPI_TXMARK` (`0x1004_0050`) sets the watermark count that triggers a pending interrupt flag in `SPI_IP` (`0x1004_0074`) when the FIFO falls below the threshold.

### Register Offsets (Base: `0x1004_0000`)
- `0x1004_0000` (`+0x00`): `SPI_SCKDIV` (Clock divider)
- `0x1004_0048` (`+0x48`): `SPI_TXDATA` (Bits 7:0 = Data; Bit 31 = `FIFO FULL`)
- `0x1004_004C` (`+0x4C`): `SPI_RXDATA` (Bits 7:0 = Data; Bit 31 = `FIFO EMPTY`)
- `0x1004_0050` (`+0x50`): `SPI_TXMARK` (Transmit Watermark Level: 0 to 7)
- `0x1004_0070` (`+0x70`): `SPI_IE` (Interrupt Enable)
- `0x1004_0074` (`+0x74`): `SPI_IP` (Interrupt Pending: Bit 0 = TX Watermark, Bit 1 = RX Watermark)

---

### Step-by-Step HTerm Procedure

1. **Halt CPU**:
   ```text
   C 0202
   ```
2. **Configure slow clock divider** (so FIFO doesn't empty instantly):
   ```text
   A 10040000
   W 00000fff
   ```
3. **Configure TX Watermark to trigger when $\le 2$ entries remain**:
   ```text
   A 10040050
   W 00000002
   ```
4. **Burst-write 8 bytes to saturate the TX FIFO**:
   ```text
   A 10040048
   W 00000011
   A 10040048
   W 00000022
   A 10040048
   W 00000033
   A 10040048
   W 00000044
   A 10040048
   W 00000055
   A 10040048
   W 00000066
   A 10040048
   W 00000077
   A 10040048
   W 00000088
   ```
5. **Check FIFO Full Flag** (Read `SPI_TXDATA`):
   ```text
   A 10040048
   R
   ```
   *Expected Response*: `R 0x80000000` (Bit 31 = 1 indicates FIFO is full).
6. **Check Watermark Pending Flag in `SPI_IP`**:
   ```text
   A 10040074
   R
   ```
   *Expected*: Bit 0 is `0` while FIFO contains $>2$ bytes. As the SPI transmitter shifts bits out and FIFO drops to $\le 2$ bytes, Bit 0 flips to `1` (`R 0x00000001`).

---

## Method 6: Non-Intrusive Hardware Execution Latency Profiling

### Principle
Rather than verifying merely *functional correctness*, use the real-time `mtime` counter as a hardware stopwatch to measure the exact cycle latency and bus-stall duration of:
- The 1TOPS neural net / multiplier accelerator at `0x3000_0000`.
- Bus bridge traversals (AHB $\rightarrow$ APB roundtrip latency).
- Memory wait states under instruction execution.

---

### Assembly Benchmark Program: `profile_accel.S`

Save as `../software/profile_accel.S`:

```assembly
# profile_accel.S - Measures exact hardware latency of Accelerator
.section .text
.globl _start

_start:
    # Base pointer to CLINT (0x0200_0000)
    lui   s0, 0x02000
    # Base pointer to Accelerator (0x3000_0000)
    lui   s1, 0x30000
    # Base pointer to DMem Results (0x8000_2000)
    lui   s2, 0x80002

    # Inputs for accelerator: 12 * 10
    li    a0, 12
    li    a1, 10

    # 1. Sample START mtime (Offset 0xBFF8)
    lw    t0, 0xbff8(s0)

    # 2. Trigger Accelerator Transaction
    sw    a0, 0x0(s1)         # Write Operand A
    sw    a1, 0x4(s1)         # Write Operand B
    lw    a2, 0x8(s1)         # Read Product

    # 3. Sample END mtime
    lw    t1, 0xbff8(s0)

    # 4. Compute Duration: elapsed = t1 - t0
    sub   t2, t1, t0

    # 5. Store Results to Data RAM
    sw    a2, 0x000(s2)       # 0x80002000 = Product (120 = 0x78)
    sw    t2, 0x004(s2)       # 0x80002004 = Elapsed Clock Cycles

done:
    wfi
    j     done
```

### Execution & Inspection

1. **Compile & Upload**:
   ```bash
   cd ../software
   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld profile_accel.S -o profile_accel.elf
   riscv-none-elf-objcopy -O binary --only-section=.text profile_accel.elf profile_accel.bin
   cp profile_accel.bin ../fpga/
   ```
2. **In HTerm**:
   ```text
   C 0202
   A 80000000
   U <byte_count>      # Send profile_accel.bin
   C 0201
   C 0101
   C 0102
   ```
3. **Read Results**:
   ```text
   C 0202              # Halt CPU
   A 80002000          # Check Accelerator Product
   R
   ```
   *Expected Product*: `R 0x00000078` ($120_{10}$).
   ```text
   A 80002004          # Check Latency (Cycles)
   R
   ```
   *Expected Latency*: Exact elapsed cycle count (typically 6–10 clock cycles including bus handshakes).

---

## 9. Quick-Reference Summary Table

| Test Target | Address | Method | Diagnostic Objective |
| :--- | :--- | :--- | :--- |
| **UART Scratchpad** | `0x1000_0007` | Zero-CPU Write/Read (`W 55`, `W AA`) | APB bus bridge integrity & `HWSTRB` subword decoding |
| **UART Loopback** | `0x1000_0004` | `MCR[4]=1`, write `THR`, poll `LSR` | Baud generator, serializer, RX/TX FIFOs |
| **CLINT Rate** | `0x0200_BFF8` | Differential read over 2 seconds | 50 MHz clock tree liveness while CPU halted |
| **CLINT Rollover** | `0x0200_BFFC` | Pre-load `0xFFFF_FFE0`, read high word | 64-bit counter ripple / carry propagation |
| **CLINT Trap** | `0x0200_0000` | Write `1` to `MSIP` while CPU in `wfi` | Live interrupt injection, `mtvec`, CSR trap entry |
| **GPIO Polarity** | `0x1006_0040` | Write `OUT_XOR`, read loopback/output | Output inversion XOR logic without wiring |
| **SPI Backpressure** | `0x1004_0048` | Burst 8 writes to `TXDATA`, check bit 31 | Hardware FIFO saturation & flow-control |
| **Latency Profiler**| `0x3000_0000` | Differential `mtime` wrap around MMIO | Cycle-accurate hardware profiling |
