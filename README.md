# 1Tops SoC Repository

This repository contains the RTL source code for the `1tops_soc`, a minimal 32-bit RISC-V System-on-Chip (SoC) specifically designed as a bare-metal controller for a Convolutional Tsetlin Machine Accelerator.

## Contents
* **`1tops_soc/`**: Contains the complete SystemVerilog RTL source tree and configuration files.
* **`1tops_soc/README.md`**: The primary documentation detailing the SoC architecture, memory map, accelerator integration, and ASIC implementation flows.
* **`build_vivado.tcl`**: A single-click Vivado project generation script.

## Getting Started with Vivado
To quickly open the RTL in Vivado for synthesis or debugging, run the following command in this root directory:

```bash
vivado -mode gui -source build_vivado.tcl
```
This will automatically generate a new project (`vivado_workspace/`), import all the necessary `1tops_soc` RTL files, configure the include paths, and set the correct top-level module (`wallypipelinedsoc`).

## Accelerator & Debug Unit Integration
Please see the [1tops_soc/README.md](1tops_soc/README.md) for detailed instructions on how the Convolutional Tsetlin Machine and Debug Units are integrated into the AHB and APB memory maps without modifying the core.
