# CORE-V-Wally Minimal 32-Bit RISC-V Core & SoC (1tops_soc)
## Complete RTL Source Package

This directory (`1tops_soc`) contains the complete, self-contained SystemVerilog RTL source code for the `1tops_soc` CORE-V-Wally RISC-V SoC architecture.

---

## Table of Contents
1. [Directory Contents & File Inventory](#1-directory-contents--file-inventory)
2. [Hardware Specifications](#2-hardware-specifications)
3. [Architecture Overview & RTL Hierarchy](#3-architecture-overview--rtl-hierarchy)
4. [Tsetlin Machine Accelerator & Debug Unit Integration](#4-tsetlin-machine-accelerator--debug-unit-integration)
5. [Software C-Compilation & Verilator Simulation](#5-software-c-compilation--verilator-simulation)


---

## 1. Directory Contents & File Inventory

```text
1tops_soc/
├── filelist.f            # Master synthesis/simulation filelist manifest
├── README.md             # Technical documentation & ASIC implementation guide
├── config/               # Top-level SystemVerilog configuration header files
│   ├── config.vh         # 1tops_soc parameter configuration (XLEN=32, RV32I bare-metal)
│   └── ...
└── src/                  # Complete SystemVerilog RTL source tree
    ├── wally/            # Top-level SoC (wallypipelinedsoc.sv) & Core
    ├── uncore/           # AHB/APB bus, RAM, ROM, CLINT, PLIC, UART, GPIO, SPI
    └── ...               # Core logic (IFU, IEU, LSU, etc.)
```

---

## 2. Features & Hardware Specifications

### Core Architecture
* **ISA**: 32-bit RISC-V Base Integer Instruction Set (`RV32I`).
* **Pipeline**: 5-stage in-order pipeline (Fetch, Decode, Execute, Memory, Writeback).
* **Execution Mode**: Bare-metal Machine Mode (`M-mode`) only, optimized for deeply embedded control tasks without the overhead of User or Supervisor modes.
* **Prefetch**: 2KB instruction prefetch buffer to hide memory latency during sequential execution.

### Memory System
* **Instruction Memory**: 16 KB on-chip SRAM mapped at `0x8000_0000`.
* **Data Memory**: 16 KB on-chip SRAM mapped at `0x8000_0000` (Unified physically, split logically or accessed via arbitration).
* **Boot ROM**: 4 KB on-chip ROM mapped at `0x0000_1000` for initial boot sequence and reset vectors.

### Peripherals & Interrupts
* **CLINT (Timer)**: Core Local Interruptor providing standard RISC-V timer (`mtime`/`mtimecmp`) and software interrupts. Mapped at `0x0200_0000`.
* **PLIC (External)**: Platform-Level Interrupt Controller for routing external peripheral interrupts to the core. Mapped at `0x0C00_0000`.
* **UART**: Industry-standard 16550D UART for serial communication and console debugging. Mapped at `0x1000_0000`.
* **GPIO**: 32-pin General Purpose I/O controller for bit-banging and simple external signaling. Mapped at `0x1000_2000`.
* **SPI**: Serial Peripheral Interface controller for interacting with external sensors or flash memory. Mapped at `0x1004_0000`.

### Accelerator & Debug Capabilities
* **Convolutional Tsetlin Machine Accelerator**: A dedicated 16MB external memory space (`0x3000_0000` - `0x30FF_FFFF`) is mapped directly to the top-level AHB bus via `HSELEXT`, allowing the CPU to seamlessly configure and control an external accelerator without routing through complex bus bridges.
* **Custom Debug Unit**: A dedicated APB slot (`PSEL[5]` at `0x0A00_0000`) is reserved as a placeholder for a custom hardware debug unit.

| Parameter | Setting | Description |
| :--- | :--- | :--- |
| **ISA Base** | `RV32I` | 32-Bit RISC-V Base Integer Instruction Set |
| **Privilege Mode** | `Machine` | Bare-metal execution (No U-mode or S-mode) |
| **Instruction SRAM**| `16 KB` | Mapped at `0x8000_0000` |
| **Data SRAM** | `16 KB` | Mapped at `0x8000_0000` |
| **Boot ROM** | `4 KB` | Mapped at `0x0000_1000` |
| **CLINT (Timer)** | `0x0200_0000` | Core Local Interruptor (Software & Timer interrupts) |
| **PLIC (External)** | `0x0C00_0000` | Platform-Level Interrupt Controller |
| **UART 16550** | `0x1000_0000` | 16550D UART |
| **GPIO** | `0x1000_2000` | 32-bit General Purpose I/O peripheral |
| **SPI** | `0x1004_0000` | Serial Peripheral Interface controller |
| **Debug Unit** | `0x0A00_0000` | Placeholder for Custom Debug Unit (APB Slot 5) |
| **Tsetlin Machine**| `0x3000_0000` | External AHB mapping for Convolutional Tsetlin Machine |

---

## 3. Architecture Overview & RTL Hierarchy

```text
+-------------------------------------------------------------------------+
|                    wallypipelinedsoc (Top-Level)                        |
|                                                                         |
|  +--------------------------------+   +------------------------------+  |
|  |       wallypipelinedcore       |   |            uncore            |  |
|  |                                |   |                              |  |
|  |  +-----+  +-----+  +-----+     |   |  +------------------------+  |  |
|  |  | IFU |  | IEU |  | LSU |     |   |  |     32-Bit AHB Bus     |  |  |
|  |  +-----+  +-----+  +-----+     |   |  +------------------------+  |  |
|  |                                |   |     |       |       |        |  |
|  |  +------+ +-------+ +-----+    |   | +------+ +------+ +--------+ |  |
|  |  | PRIV | | HAZ   | | EBU |<========>| RAM  | | ROM  | | BRIDGE | |  |
|  |  +------+ +-------+ +-----+    |   | | 16KB | | 4KB  | | (APB)  | |  |
|  +--------------------------------+   | +------+ +------+ +--------+ |  |
|                                       |                        |     |  |
|                                       |  +-------+ +------+ +------+ |  |
|                                       |  | CLINT | | PLIC | | UART | |  |
|                                       |  +-------+ +------+ +------+ |  |
|                                       |  | GPIO  | | SPI  | | DEBUG| |  |
|                                       |  +-------+ +------+ +------+ |  |
|                                       +------------------------------+  |
+-------------------------------------------------------------------------+
                                || External AHB (0x3000_0000)
                    +------------------------------------+
                    |  Convolutional Tsetlin Machine     |
                    +------------------------------------+
```

---

## 4. Tsetlin Machine Accelerator & Debug Unit Integration

### Tsetlin Machine Integration (`0x3000_0000`)
The system is explicitly designed to act as a bare-metal controller for an external Convolutional Tsetlin Machine.
The accelerator space is mapped to `0x3000_0000` - `0x30FF_FFFF` (16MB).
Because it uses the `EXT_MEM` parameter configuration, any memory access by the core to this region is automatically routed out of the top-level `wallypipelinedsoc.sv` module via the `HSELEXT` and `HRDATAEXT` pins.

We have provided a template accelerator and testbench to show how this is connected:
- **`src/accelerator/tsetlin_ahb_wrapper.sv`**: A mock SystemVerilog AHB peripheral mapped to `0x3000_0000`. You should put your actual Tsetlin Machine logic in this file (or replace it).
- **`filelist.f`**: This manifest includes `src/accelerator/*.sv` so your accelerator is automatically picked up by Vivado and Verilator.
- **`testbench/tb.sv`**: This is the top-level testbench that instantiates both `wallypipelinedsoc` and `tsetlin_ahb_wrapper`, connecting the exported AHB pins (`HSELEXT`, `HADDREXT`, etc.) directly to the accelerator.

### Debug Unit Integration
The `SDC` APB peripheral slot has been repurposed as a placeholder for a custom Debug Unit.
In `src/uncore/uncore.sv`, look for the `debug_unit` block. You can connect your custom debug module directly to the APB bus signals `PSEL[5]`, `PADDR`, `PWDATA`, and `PRDATA[5]` located there.

---

## 5. Software C-Compilation & Verilator Simulation

This repository includes a bare-metal C toolchain scaffold and a Verilator simulator driver so you can write C code, compile it, and run it against the RTL (and your accelerator).

### 1. Writing C Code (`software/`)
The `software/` directory contains everything you need to write and compile code for the `1tops_soc`:
- `main.c`: Your main application. It demonstrates how to print to the UART (`0x1000_0000`) and how to read/write memory-mapped registers in the Tsetlin Accelerator (`0x3000_0000`).
- `link.ld`: A minimal linker script mapping code and data directly to the 16KB SRAM block.
- `crt0.S`: Assembly startup script to initialize the stack and jump to `main`.
- `Makefile`: Uses `riscv64-unknown-elf-gcc` to compile the C files and generates a `test.mem` hex file.

### 2. Simulating with Verilator (`testbench/`)
The `testbench/` directory contains a complete simulation environment.

**Prerequisites:**
You need `verilator` and `riscv64-unknown-elf-gcc` installed on your machine.

**Running the Simulation:**
Navigate to the testbench directory and run `make run`:
```bash
cd testbench
make run
```

**What happens when you type `make run`:**
1. It builds the Verilator C++ model of `tb.sv` (which includes the SoC and the Accelerator).
2. It copies the `software/test.mem` (your compiled C code) into the testbench directory.
3. It runs the simulation. The internal `ram1p1rwbe.sv` memory module uses `$readmemh("test.mem")` to preload your C code into the 16KB SRAM.
4. The simulation executes, and a `trace.vcd` waveform is generated for debugging in GTKWave!
