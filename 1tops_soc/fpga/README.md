# CORE-V Wally RISC-V SoC: Dedicated FPGA Implementation (Basys 3)

This directory contains the standalone, FPGA-tuned implementation of the **CORE-V Wally RISC-V SoC (`1tops_soc`)** with fully integrated **Dual-Protocol Hardware Debugger (UART + FT1248)**, **Hardware Core Step Controller**, **Reconfigurable Clock Dividers**, **Block RAM memory tuning**, and physical pin constraints for the **Digilent Basys 3** board (`xc7a35tcpg236-1`).

---

## 1. Directory Structure

```
1tops_soc/fpga/
├── config/              # Wally SoC configuration (config.vh, parameter-defs.vh)
├── constrs/
│   └── basys3.xdc       # Complete physical pin constraints for Basys 3
├── src/                 # Full synthesizable SoC RTL tree
│   ├── accelerator/     # 1TOPS neural net accelerator / multiplier (0x3000_0000)
│   ├── debugger/        # riscv_debugger_top, socdebug_uart, socdebug_ft1248, core_step_controller, ahb_mux
│   │   ├── sw/          # Host software: dbg_cli.py
│   │   └── tb/          # Complete dual-protocol testbench (tb_debugger.sv)
│   ├── generic/mem/     # FPGA-tuned ram1p1rwbe.sv (Block RAM inferred)
│   ├── uncore/          # APB bridge, GPIO, CLINT, PLIC, 16550 Uncore UART
│   └── wally/           # wallypipelinedcore, wallypipelinedsoc (with integrated debugger)
├── top/
│   └── wally_soc_fpga_top.sv # Top-level FPGA wrapper wiring clocks, resets, pads
├── build_fpga.tcl       # Automated Vivado project creation and build script
├── test_step_and_clkdiv.py   # Automated Python test runner for step execution & clock dividers
├── sim_step_and_clkdiv.sh    # Automated Vivado XSIM simulation script
├── STEP_AND_CLOCK_DIV_VERIFICATION_GUIDE.md # In-depth architectural & verification manual
├── PERIPHERAL_VERIFICATION_GUIDE.md         # MMIO peripheral probing guide
├── step_test.bin        # 64-byte deterministic assembly test program for step verification
├── factorial.bin        # 76-byte factorial test program
└── README.md            # This documentation
```

---

## 2. Key FPGA-Tuned & Subsystem Architecture Modifications

### A. True Block RAM Inference (`src/generic/mem/ram1p1rwbe.sv`)
- **ASIC vs FPGA Challenge**: The original generic memory used combinational read (`assign dout = RAM[addrd]`), which forces FPGA synthesis to map the 16 KB memory into thousands of slice flip-flops and LUTRAMs, exceeding the Artix-7 35T capacity.
- **FPGA Tuning**: In `fpga/src/generic/mem/ram1p1rwbe.sv`, the memory is tagged with `(* ram_style = "block" *)` and uses synchronous read registers (`dout_reg <= RAM[addr]`) with byte-write enables (`bwe`).
- **Result**: Vivado synthesizes instruction RAM (`ram_i`) and data RAM (`ram_d`) directly into dedicated hardware **`RAMB36E1` Block RAM primitives** (taking only 4 BRAM tiles out of the 50 available on Basys 3).

### B. Hardware-Controlled Core Single-Step Execution (`src/debugger/core_step_controller.sv`)
- **Non-Intrusive Core Freeze & Single-Stepping**:
  - Halts the CPU pipeline stages via `ExternalStall` in `hazard.sv`.
  - Supports **Instruction Step (`C 0204`)**: Releases stall until `InstrRetired` pulses from Writeback (`InstrValidM & ~StallW & ~FlushW`), then re-freezes the core immediately.
  - Supports **Clock-Cycle Step (`C 020c`)**: Releases stall for **exactly 1 clock cycle**, advancing the pipeline by one tick.
  - Features an internal 65,536-cycle watchdog safety timer to prevent permanent deadlocks.

### C. Reconfigurable In-Flight Clock Dividers (`socdebug_uart.v` & `socdebug_ft1248_control.v`)
- **Isolated Hardware Registers**: Divided clock rates for both UART and FT1248 interfaces can be queried and modified at runtime via commands `B` and `D`.
- **Glitch-Free Latching**: The UART baud divider only updates when both RX and TX engines are idle (`rx_state == RX_IDLE && tx_state == TX_IDLE && !s_axis_tvalid`), ensuring framing bits and echoes are never corrupted mid-flight.

### D. Direct Auto-Prompt on Boot
- On power-on or board reset (`btnC`), the controller sends ` 0x50c1ab04\r\n` and **directly auto-enters ADP command mode with prompt `]`**. No escape character (`0x1B`) is required.

### E. Subword-Accurate HWSTRB Byte Decoding (`src/wally/wallypipelinedsoc.sv`)
- Dynamic decoding of `dbg_HWSTRB` prevents subword binary upload (`U`) corruption:
  - Word (`HSIZE = 2'b10`): `4'b1111`
  - Halfword (`HSIZE = 2'b01`): `HADDR[1] ? 4'b1100 : 4'b0011`
  - Byte (`HSIZE = 2'b00`): Decoded from `HADDR[1:0]` (`4'b0001`, `4'b0010`, `4'b0100`, or `4'b1000`)

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

## 5. Automated Verification Tools

### A. Vivado XSIM RTL Simulation (Single-Command Run)
Runs the self-checking SystemVerilog testbench (`tb/tb_debugger.sv`), executing all 26 test assertions for Part 4 (Step FSM) and Part 5 (Clock Dividers):
```bash
./sim_step_and_clkdiv.sh
```

### B. Automated Python Test Suite (`test_step_and_clkdiv.py`)
Run without hardware using the built-in simulator:
```bash
python3 test_step_and_clkdiv.py --mock
```
Run against physical hardware on Basys 3:
```bash
python3 test_step_and_clkdiv.py --protocol uart --device /dev/ttyUSB0 --baud 115200
```

---

## 6. Testing via Python CLI (`src/debugger/sw/dbg_cli.py`)

### A. Core Control & Stepping:
```bash
# Query status (halt, busy, done flags)
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 status

# Halt CPU pipeline
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 halt

# Single-step exactly 1 retired instruction
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 step

# Single-step exactly 1 clock cycle
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 step_cycle

# Resume free-running execution
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 resume
```

### B. Memory & Peripheral Access:
```bash
# Read/Write 32-bit memory
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 read 0x80000000
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 write 0x80002000 0xdeadbeef

# Compute with Accelerator Multiplier
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 read_accel
```

### C. Clock Divider Configuration:
```bash
# Read current UART and FT1248 clock dividers
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 get_dividers

# Set UART divider (e.g. 217 for 230,400 baud at 50 MHz)
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 set_uart_div 217

# Set FT1248 divider (e.g. 8)
python3 src/debugger/sw/dbg_cli.py --protocol uart --device /dev/ttyUSB0 set_ft_div 8
```

---

## 7. Interactive Serial Terminal Guide (HTerm)

Configure HTerm with **115200 Baud, 8 Data Bits, 1 Stop Bit, No Parity, Send on Enter = `CR`**:

1. **Boot / Reset Banner & Auto-Prompt**:
   When the FPGA powers on or when center pushbutton `btnC` is pressed, the debugger automatically displays:
   ```text
    0x50c1ab04
   ]
   ```
   LED 15 turns solidly ON.

2. **Core Stepping Commands**:
   - `C 0202` — Halt CPU pipeline (`led_core_halted` turns ON).
   - `C 0204` followed by `C 0104` — Single-step 1 retired instruction.
   - `C 020c` followed by `C 010c` — Single-step 1 clock cycle.
   - `C` — Read status: `C 0x<GPI8><GPO8>0000` (GPI8: Bit 0 = Halted, Bit 1 = Step Busy, Bit 2 = Step Done).
   - `C 0102` — Resume CPU pipeline execution (`led_core_halted` turns OFF).

3. **Clock Divider Commands (`B` & `D`)**:
   - `B` — Query dividers: `B 0x00<FT8><UART16>` (e.g. `B 0x000101b2` for 50 MHz FPGA).
   - `B 00d9` — Reconfigure UART to 230,400 baud.
   - `D` — Query FT1248 divider: `D 0x01`.
   - `D 08` — Reconfigure FT1248 divider to 8.

---

## 8. Common Baud Rate Divider Table (50 MHz FPGA Clock)

$$\text{UART Divider} = \text{round}\left(\frac{50{,}000{,}000}{\text{Baud Rate}}\right)$$

| Desired Baud Rate | Divider (Dec) | Divider Hex (`B <hex>`) | Actual Baud Rate | Error % |
| :--- | :---: | :---: | :---: | :---: |
| **115,200 Baud** *(Default)* | `434` | `0x01B2` | 115,207 | +0.006% |
| **230,400 Baud** | `217` | `0x00D9` | 230,415 | +0.006% |
| **460,800 Baud** | `109` | `0x006D` | 458,716 | -0.45% |
| **921,600 Baud** | `54` | `0x0036` | 925,926 | +0.47% |
| **1,500,000 Baud** | `33` | `0x0021` | 1,515,152 | +1.01% |
| **3,000,000 Baud** | `17` | `0x0011` | 2,941,176 | -1.96% |

---

## 9. Single-Step Verification Walkthrough (`step_test.bin`)

The repository includes a dedicated 64-byte stepping verification binary (`step_test.bin` from `../software/step_test.S`):

1. **Halt CPU**: `C 0202`
2. **Zero DRAM**: `A 80002000` $\rightarrow$ `V 00000000` $\rightarrow$ `F 08`
3. **Upload `step_test.bin`**: `A 80000000` $\rightarrow$ `U 40` $\rightarrow$ send `step_test.bin` in HTerm.
4. **Reset PC to 0x80000000**: `C 0201` $\rightarrow$ `C 0101`
5. **Step Instructions**:
   - Send `C 0204` then `C 0104` four times.
   - Read Data RAM: `A 80002000` $\rightarrow$ `R` $\rightarrow$ replies `R 0x11111111`!
   - Send `C 0204` then `C 0104` three more times.
   - Read Data RAM: `A 80002004` $\rightarrow$ `R` $\rightarrow$ replies `R 0x22222222`!
   - Send `C 0204` then `C 0104` three more times.
   - Read Data RAM: `A 80002008` $\rightarrow$ `R` $\rightarrow$ replies `R 0x33333333`!
6. **Resume CPU**: `C 0102`

For detailed information, refer to [STEP_AND_CLOCK_DIV_VERIFICATION_GUIDE.md](file:///home/ganesh/Desktop/shri/cvw/1tops_soc/fpga/STEP_AND_CLOCK_DIV_VERIFICATION_GUIDE.md).
