# CORE-V Wally RISC-V SoC: Dedicated FPGA Implementation (Basys 3)

This directory contains the standalone, FPGA-tuned implementation of the **CORE-V Wally RISC-V SoC (`1tops_soc`)** with fully integrated **Dual-Protocol Hardware Debugger (UART + FT1248)**, **Block RAM memory tuning**, and physical pin constraints for the **Digilent Basys 3** board (`xc7a35tcpg236-1`).

---

## 1. Directory Structure

```
1tops_soc/fpga/
├── config/              # Wally SoC configuration (config.vh, parameter-defs.vh)
├── constrs/
│   └── basys3.xdc       # Complete physical pin constraints for Basys 3
├── src/                 # Full synthesizable SoC RTL tree
│   ├── accelerator/     # 1TOPS neural net accelerator / multiplier (0x3000_0000)
│   ├── debugger/        # riscv_debugger_top, socdebug_uart, socdebug_ft1248, ahb_mux
│   ├── generic/mem/     # FPGA-tuned ram1p1rwbe.sv (Block RAM inferred)
│   ├── uncore/          # APB bridge, GPIO, CLINT, PLIC, 16550 Uncore UART
│   └── wally/           # wallypipelinedcore, wallypipelinedsoc (with integrated debugger)
├── top/
│   └── wally_soc_fpga_top.sv # Top-level FPGA wrapper wiring clocks, resets, pads
├── build_fpga.tcl       # Automated Vivado project creation and build script
└── README.md            # This documentation
```

---

## 2. Key FPGA-Tuned Modifications

### A. True Block RAM Inference (`src/generic/mem/ram1p1rwbe.sv`)
- **ASIC vs FPGA Challenge**: The original generic memory used combinational read (`assign dout = RAM[addrd]`), which forces FPGA synthesis to map the 16 KB memory into thousands of slice flip-flops and LUTRAMs, exceeding the Artix-7 35T capacity.
- **FPGA Tuning**: In `fpga/src/generic/mem/ram1p1rwbe.sv`, the memory is tagged with `(* ram_style = "block" *)` and uses synchronous read registers (`dout_reg <= RAM[addr]`) with byte-write enables (`bwe`).
- **Result**: Vivado synthesizes instruction RAM (`ram_i`) and data RAM (`ram_d`) directly into dedicated hardware **`RAMB36E1` Block RAM primitives** (taking only 4 BRAM tiles out of the 50 available on Basys 3).

### B. Complete Hardware Debugger Integration (`src/wally/wallypipelinedsoc.sv`)
- **2-Master AHB-Lite Bus Arbiter (`ahb_mux.sv`)**: Multiplexes between the CPU Core (Master 0) and the Debugger Subsystem (Master 1).
- **Non-Intrusive Core Freeze**: When `core_halt_o = 1`, `wallypipelinedsoc` asserts `ExternalStall` into the CPU hazard unit, freezing all 5 pipeline stages in place without altering registers.
- **Exclusive Bus Priority**: While halted, the debugger gains unconditional priority to read/write instruction memory (`0x8000_0000`), data memory (`0x8000_2000`), boot ROM, and accelerator registers (`0x3000_0000`).

### C. Subword-Accurate HWSTRB Byte Decoding (`src/wally/wallypipelinedsoc.sv`)
- **Subword Overwrite Bug**: In the original uncore AHB interface, `HWSTRB` was hardcoded to `4'b1111` whenever the debugger held `dbg_core_halt = 1`. During single-byte or halfword transfers (e.g. streaming binary bytes via `U <count>`), this inadvertently caused the entire 32-bit word to be written with replicated byte lanes, corrupting adjacent bytes.
- **Dynamic Decoding Fix**: Replaced with `dbg_HWSTRB` decoding logic:
  - Word (`HSIZE = 2'b10`): `4'b1111`
  - Halfword (`HSIZE = 2'b01`): `HADDR[1] ? 4'b1100 : 4'b0011`
  - Byte (`HSIZE = 2'b00`): Decoded from `HADDR[1:0]` (`4'b0001`, `4'b0010`, `4'b0100`, or `4'b1000`)
- **Result**: Arbitrary byte-stream uploads (`U`) and subword reads/writes operate correctly without corrupting neighboring memory bytes.

### D. Glitch-Free Synchronous UART RX Monitor & Activity LED (`top/wally_soc_fpga_top.sv`)
- **Combinational Loop Prevention**: Replaced asynchronous unclocked level-toggle logic with a clean synchronous receiver FSM clocked by 50 MHz `clk_soc` with a 2-stage metastability synchronizer.
- **Visual Feedback**:
  - Blinks **LED 15 (`led_rx_detect` on Pin L1)** with a 200 ms monostable pulse stretcher whenever any valid UART byte arrives.
  - Latches **LED 15 solidly ON** upon successfully detecting the prompt character `]` (`0x5D`), providing instant visual confirmation that the ADP engine has entered command mode.

---

## 3. Physical Hardware Pinout (Basys 3)

| Port Name | Board Location | Direction | Function |
| :--- | :--- | :---: | :--- |
| `clk` | **Pin W5** | Input | 100 MHz on-board oscillator (MMCM produces 50 MHz `clk_soc`) |
| `reset_btn` | **Pin U18 (btnC)** | Input | Center pushbutton (active-high system reset; OR'd with MMCM lock) |
| `dbg_sel` | **Pin V17 (SW0)** | Input | Slide switch: `0` (Down) = UART, `1` (Up) = FT1248 |
| `uart_rx` | **PMOD JA Pin 1 (J1)** | Input | Debugger UART RX (connect to USB-UART Dongle TXD) |
| `uart_tx` | **PMOD JA Pin 2 (L2)** | Output | Debugger UART TX (connect to USB-UART Dongle RXD) |
| `ft1248_clk` | **PMOD JB Pin 1 (A14)** | Output | FT1248 Serial Clock (SCLK to FT232H) |
| `ft1248_ss_n` | **PMOD JB Pin 2 (A16)** | Output | FT1248 Active-Low Chip Select (SS# to FT232H) |
| `ft1248_miso` | **PMOD JB Pin 3 (B15)** | Input | FT1248 Read Available Status (MISO / RXF# from FT232H) |
| `ft1248_miosio` | **PMOD JB Pin 4 (B16)** | Inout | FT1248 Bidirectional Serial Data Bus |
| `UARTSin` | *Pin B18 (Unused)* | Input | Uncore Application UART RX (tied high in top-wrapper) |
| `UARTSout` | *Pin A18 (Unused)* | Output | Uncore Application UART TX (unconnected in top-wrapper) |
| `led_core_halted` | **Pin U16 (LED 0)** | Output | Status LED (lit when CPU core is halted by debugger) |
| `led_dbg_sel` | **Pin E19 (LED 1)** | Output | Status LED (lit when FT1248 mode is selected) |
| `led_rx_detect` | **Pin L1 (LED 15)** | Output | UART RX Activity / Prompt `]` Detector (Blinks ~200ms on any byte, latches ON upon detecting `]`) |

---

## 4. How to Build the Bitstream in Vivado

```bash
cd 1tops_soc/fpga

# Option 1: Open project directly in Vivado GUI
vivado -mode gui -source build_fpga.tcl

# Option 2: Run batch synthesis & implementation
vivado -mode batch -source build_fpga.tcl
```

Once the project opens in Vivado, click **Generate Bitstream** in the Flow Navigator.

---

## 5. Testing from Host PC

### A. UART Debug Mode (`SW0` Down = `0`):
Connect your USB-to-UART dongle to PMOD JA (Pin 1 = RX, Pin 2 = TX, Pin 5 = GND):
```bash
# Check status and halt CPU
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 halt

# Read IRAM / DRAM
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 read 0x80000000
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 write 0x80002000 0xdeadbeef

# Compute with Accelerator Multiplier
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 write_accel 8 9
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 read_accel

# Resume CPU
python3 sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 resume
```

### B. FT1248 High-Speed Mode (`SW0` Up = `1`):
Connect your FT232H breakout board to PMOD JB:
```bash
python3 sw/dbg_cli.py --protocol ft1248 --ftdi-url ftdi://ftdi:232h/1 halt
python3 sw/dbg_cli.py --protocol ft1248 --ftdi-url ftdi://ftdi:232h/1 read_accel
python3 sw/dbg_cli.py --protocol ft1248 --ftdi-url ftdi://ftdi:232h/1 resume
```

---

## 6. Interactive Serial Terminal Guide (HTerm / Minicom)

You can communicate directly with the on-chip ASCII Debug Protocol (ADP) engine using **HTerm** (115200 Baud, 8-N-1, No Flow Control):

1. **Boot / Reset Banner**:
   When the FPGA powers on or when center pushbutton `btnC` is pressed, the debugger outputs:
   ```text
   0x50c1ab04
   ```
2. **Enter Command Mode (`<ESC>` / `0x1B`)**:
   * In HTerm, set Input type to **`HEX`**, type `1B`, and send.
   * The board will immediately reply with `]`. (Status LED 15 on Pin L1 also turns solidly ON upon detecting `]`).
3. **Execute Commands**:
   * Set Input type back to **`ASC`** with **Send on Enter = `CR`**.
   - Query status: `C` $\rightarrow$ replies `C 0x01000000`.
   - Exit command mode back to terminal passthrough: `X`.

> [!TIP]
> **Auto-Prompt on Boot Option**: If you prefer the debugger to output the prompt `]` automatically upon reset without having to type `<ESC>` / `0x1B`, you can uncomment line 137 and line 737 in `src/debugger/socdebug_adp_control.v` and rebuild the bitstream.

---

## 7. Factorial Program Demo (`factorial.bin`)

The repository includes a bare-metal RV32I test program ([`../software/factorial.S`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/software/factorial.S) $\rightarrow$ `factorial.bin`, 76 bytes / `0x4C` bytes) that reads $n$ from Data Memory `0x80002000`, calculates $n!$, and writes the product to `0x80002004`.

### Building `*.bin` from `*.S` Assembly

If you need to recompile `factorial.bin` or compile a new assembly test program (`<program>.S` $\rightarrow$ `<program>.bin`) for execution on the FPGA:

#### Prerequisites
Ensure the GNU RISC-V bare-metal toolchain is in your `PATH`:
- Supported toolchain prefixes: `riscv-none-elf-` or `riscv64-unknown-elf-`
- Check availability:
  ```bash
  which riscv-none-elf-gcc || which riscv64-unknown-elf-gcc
  ```

#### Method 1: Using the Software Makefile (Recommended)
From either the `fpga/` directory or `software/` directory:
```bash
# From 1tops_soc/fpga:
make -C ../software factorial.bin

# Or navigate to 1tops_soc/software directly:
cd ../software
make factorial.bin
```
The Makefile automatically detects the installed RISC-V compiler prefix (`riscv-none-elf-` or `riscv64-unknown-elf-`), compiles `factorial.S` against `link.ld`, extracts the `.text` section with `objcopy`, and copies `factorial.bin` into `../fpga/factorial.bin`.

#### Method 2: Manual Compilation for Any Custom `*.S` Program
To compile any custom assembly file (e.g., `my_test.S`):

1. **Assemble and Link for RV32I**:
   ```bash
   cd ../software
   riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld my_test.S -o my_test.elf
   ```
   > [!IMPORTANT]
   > - `-march=rv32i -mabi=ilp32`: The Wally 1TOPS SoC implements the base RV32I instruction set without standard M/A/F/D/C extensions. Multiplications must use shift-and-add loops or the hardware accelerator at `0x3000_0000`.
   > - `-T link.ld`: Memory map locates Instruction RAM (`.text`) at `0x8000_0000` (reset vector) and Data RAM (`.data`/`.bss`) at `0x8000_2000`.

2. **Extract Pure Binary Machine Code**:
   ```bash
   riscv-none-elf-objcopy -O binary --only-section=.text my_test.elf my_test.bin
   cp my_test.bin ../fpga/
   ```

3. **Inspect Disassembly (Optional)**:
   ```bash
   riscv-none-elf-objdump -d my_test.elf
   ```

4. **Determine Byte Length for ADP Upload (`U`)**:
   Check the exact size in bytes and convert to hexadecimal:
   ```bash
   python3 -c "import os; s = os.path.getsize('my_test.bin'); print(f'Size: {s} bytes (0x{s:x})')"
   ```
   For example, a 76-byte file is `0x4C` bytes, so the ADP upload command in HTerm is `U 4c`.

---

### Step-by-Step Execution Walkthrough:

1. **Halt CPU**:
   ```text
   C 0202
   ```
   *(LED 0 `led_core_halted` turns ON).*

2. **Clear IRAM using Fill (`F`)**:
   ```text
   A 80000000
   V 00000000
   F 200
   ```
   *(Rapidly zeroes out 512 words / 2 KB of instruction memory).*

3. **Set Input $n = 5$ in Data Memory**:
   ```text
   A 80002000
   W 00000005
   W 00000000
   ```

4. **Upload Factorial Program (`U`)**:
   ```text
   A 80000000
   U 4c
   ```
   In HTerm, click **Send File**, select `factorial.bin` (76 bytes), and send.  
   The board streams all 76 bytes into IRAM and replies `U 0x0000004c` followed by `]`.

5. **Restart & Resume CPU**:
   ```text
   C 0201
   C 0101
   C 0102
   ```
   *(LED 0 turns OFF; CPU executes `factorial.bin` from reset vector `0x80000000`).*

6. **Halt & Check Result**:
   ```text
   C 0202
   A 80002004
   R
   ```
   **Expected Reply**: `R 0x00000078` ($120_{10} = 5!$).

> [!NOTE]
> **Understanding Read (`R`) Parameter Sizing**:
> - **`R` (no parameter)**: Reads **1 word (32-bit)** and prints e.g. `R 0x00000078`.
> - **`R 4` or `R 04` (1–2 hex digits)**: Interpreted as an **8-bit byte read count**. It prints 4 consecutive bytes (`R 0xXX`) broken down byte-by-byte, advancing the address by 1 byte each line.
> - **`R 0004` (4 hex digits)**: Interpreted as a **16-bit half-word read count**.
> - **`R 00000004` (8 hex digits)**: Interpreted as a **32-bit word read count**. It prints 4 consecutive 32-bit words (`R 0xXXXXXXXX`), advancing the address by 4 bytes each line.

