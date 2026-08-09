# CORE-V-Wally (my_minimal_rv32) Vivado Project & Dynamic Schematic Setup

This directory (`sample_1/schematics`) contains all necessary files, project configurations, TCL build scripts, and top-level wrappers to open, inspect, and dynamically update the RTL schematics of the **CORE-V-Wally (`my_minimal_rv32`) RISC-V SoC** in Xilinx Vivado.

---

## 📁 Directory Inventory

| File / Directory | Description |
| :--- | :--- |
| **`my_minimal_rv32_schematic/`** | Pre-built Vivado Project folder containing `my_minimal_rv32_schematic.xpr`. |
| **`wallypipelinedsocwrapper.sv`** | Fully dynamic top-level SystemVerilog wrapper module that resolves parameter `cvw_t P` from `config/config.vh` & `config/parameter-defs.vh` for Vivado schematic elaboration. |
| **`create_project.tcl`** | Tcl script to generate the Vivado project, configure include directories (`../config`, `../src`), and add all SystemVerilog RTL source files. |
| **`update_and_elaborate.tcl`** | Tcl script to dynamically rescan `src/` & `config/`, update filesets, and re-elaborate the RTL Schematic with updated feature flags. |
| **`elaborate_schematic.tcl`** | Tcl script to run RTL elaboration (`synth_design -rtl`) and open the schematic hierarchy view in Vivado. |
| **`open_vivado.sh`** | Executable shell launcher script to open Vivado GUI with automatic project & feature synchronization. |
| **`README.md`** | Setup documentation & guide. |

---

## 🔄 How Feature & Source Code Changes are Reflected

Whenever you edit features in `sample_1/config/config.vh` or add/remove RTL files in `sample_1/src/`, the Vivado project and schematics will update dynamically:

### 1. Changing Features in `config.vh`
If you enable or disable features (such as `DCACHE_SUPPORTED`, `ICACHE_SUPPORTED`, `F_SUPPORTED`, `M_SUPPORTED`, `ZMMUL_SUPPORTED`, `GPIO_SUPPORTED`, `UART_SUPPORTED`, `SPI_SUPPORTED`, `PMP_ENTRIES`, `XLEN=64`, etc.):
- **If Vivado is closed**: Run `./open_vivado.sh` or `vivado -mode gui -source update_and_elaborate.tcl`. It will automatically re-read `config.vh`, re-populate struct `P`, and re-elaborate the updated schematic.
- **If Vivado GUI is already open**: Open the **Tcl Console** at the bottom of Vivado and type:
  ```tcl
  source update_and_elaborate.tcl
  ```
  *(or press `Ctrl+R` / click **Refresh Elaborated Design** in Vivado).*

### 2. Adding or Removing RTL Files in `src/`
The `update_and_elaborate.tcl` and `create_project.tcl` scripts automatically perform glob pattern scans across `sample_1/src/` (`*.sv`, `*/*.sv`, `*/*/*.sv`, etc.). Any new module or submodule added under `src/` is automatically discovered and added to the project.

---

## 🚀 Quick Start Guide

### Launch Vivado with Automatic Dynamic Updates:
```bash
cd sample_1/schematics
./open_vivado.sh
```

### Manual TCL Execution in Vivado:
Inside Vivado GUI Tcl Console:
```tcl
source update_and_elaborate.tcl
```
This re-elaborates the design and updates the schematic hierarchy viewer.
