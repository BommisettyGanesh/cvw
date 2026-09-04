# RV32 Core — Vivado RTL Schematic Viewer

This directory contains TCL scripts, a top-level wrapper, and a pre-built Vivado project to inspect the RTL schematics of the **CORE-V-Wally RV32 Core SoC** in Xilinx Vivado.

---

## Directory Contents

| File / Directory | Description |
| :--- | :--- |
| **`rv32_core_schematic/`** | Vivado project folder containing `rv32_core_schematic.xpr`. |
| **`wallypipelinedsocwrapper.sv`** | Top-level SystemVerilog wrapper that resolves the `cvw_t P` parameter struct from `config/config.vh` and `config/parameter-defs.vh` for Vivado elaboration. |
| **`create_project.tcl`** | Creates the Vivado project, sets include directories (`../config`, `../src`), and adds all RTL sources. |
| **`update_and_elaborate.tcl`** | Rescans `src/` and `config/`, updates filesets, and re-elaborates the RTL schematic. |
| **`elaborate_schematic.tcl`** | Runs RTL elaboration (`synth_design -rtl`) and opens the schematic viewer. |
| **`open_vivado.sh`** | Shell launcher — opens Vivado GUI with automatic project sync and elaboration. |

---

## Quick Start

```bash
cd schematics
./open_vivado.sh
```

This will:
1. Clean up any stale Vivado logs/journals.
2. Create the project if it doesn't exist (or open the existing one).
3. Add all `.sv` and `.vh` files from `src/` and `config/`.
4. Elaborate the RTL and open the schematic hierarchy viewer.

---

## Reflecting Source Code or Config Changes

### Changing Features in `config/config.vh`

When you enable or disable features (e.g., `GPIO_SUPPORTED`, `UART_SUPPORTED`, `PMP_ENTRIES`, etc.):

- **If Vivado is closed**: Run `./open_vivado.sh`. It will re-read `config.vh`, rebuild the parameter struct, and re-elaborate.
- **If Vivado is already open**: In the Tcl Console, type:
  ```tcl
  source update_and_elaborate.tcl
  ```

### Adding or Removing RTL Files in `src/`

The TCL scripts automatically glob-scan `src/` for all `.sv` files at any depth. Any new module added under `src/` is automatically discovered and added to the project on the next elaboration.
