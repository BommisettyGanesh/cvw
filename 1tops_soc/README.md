# CORE-V-Wally Minimal 32-Bit RISC-V Core & SoC (1tops_soc)
## Complete RTL Source Package

This directory (`1tops_soc`) contains the complete, self-contained SystemVerilog RTL source code for the `1tops_soc` CORE-V-Wally RISC-V SoC architecture.

---

## Table of Contents
1. [Directory Contents & File Inventory](#1-directory-contents--file-inventory)
2. [Hardware Specifications](#2-hardware-specifications)
3. [Architecture Overview & RTL Hierarchy](#3-architecture-overview--rtl-hierarchy)
4. [Tsetlin Machine Accelerator & Debug Unit Integration](#4-tsetlin-machine-accelerator--debug-unit-integration)


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

## 2. Hardware Specifications

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

### Tsetlin Machine Integration
The system is explicitly designed to act as a bare-metal controller for an external Convolutional Tsetlin Machine.
The accelerator space is mapped to `0x3000_0000` - `0x30FF_FFFF` (16MB).
Because it uses the `EXT_MEM` parameter configuration, any memory access by the core to this region is automatically routed out of the top-level `wallypipelinedsoc.sv` module via the `HSELEXT` and `HRDATAEXT` pins.
You simply instantiate your Tsetlin Machine alongside `wallypipelinedsoc` and connect it to these exported AHB signals. No core modifications are required!

### Debug Unit Integration
The `SDC` APB peripheral slot has been repurposed as a placeholder for a custom Debug Unit.
In `src/uncore/uncore.sv`, look for the `debug_unit` block. You can connect your custom debug module directly to the APB bus signals `PSEL[5]`, `PADDR`, `PWDATA`, and `PRDATA[5]` located there.

---
