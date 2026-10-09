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

---

## 3. Physical Hardware Pinout (Basys 3)

| Port Name | Board Location | Direction | Function |
| :--- | :--- | :---: | :--- |
| `clk` | **Pin W5** | Input | 100 MHz on-board oscillator |
| `reset_btn` | **Pin U18 (btnC)** | Input | Center pushbutton (active-high system reset) |
| `dbg_sel` | **Pin V17 (SW0)** | Input | Slide switch: `0` (Down) = UART, `1` (Up) = FT1248 |
| `uart_rx` | **PMOD JA Pin 1 (J1)** | Input | Debugger UART RX (connect to USB-UART Dongle TXD) |
| `uart_tx` | **PMOD JA Pin 2 (L2)** | Output | Debugger UART TX (connect to USB-UART Dongle RXD) |
| `ft1248_clk` | **PMOD JB Pin 1 (A14)** | Output | FT1248 Serial Clock (SCLK to FT232H) |
| `ft1248_ss_n` | **PMOD JB Pin 2 (A16)** | Output | FT1248 Active-Low Chip Select (SS# to FT232H) |
| `ft1248_miso` | **PMOD JB Pin 3 (B15)** | Input | FT1248 Read Available Status (MISO / RXF# from FT232H) |
| `ft1248_miosio` | **PMOD JB Pin 4 (B16)** | Inout | FT1248 Bidirectional Serial Data Bus |
| `UARTSin` | **Pin B18** | Input | Uncore Application UART RX (via onboard micro-USB cable) |
| `UARTSout` | **Pin A18** | Output | Uncore Application UART TX (via onboard micro-USB cable) |
| `led_core_halted` | **Pin U16 (LED 0)** | Output | Status LED (lit when CPU core is halted by debugger) |
| `led_dbg_sel` | **Pin E19 (LED 1)** | Output | Status LED (lit when FT1248 mode is selected) |

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
