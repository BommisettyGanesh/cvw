# 1TOPS SoC

This repository contains the RTL code and documentation for the **1TOPS SoC**, which is based on the OpenHW CVW (CORE-V-WALLY) RISC-V processor. The SoC is specifically tailored for hardware synthesis and accelerator integration, stripped down to provide only the essential components for SoC generation.

## SoC Architecture

The SoC leverages an **AHB-Lite** interconnect to map the core, uncore peripherals, and custom hardware accelerators.

```text
               +-------------------------------------------------------------+
               |                                                             |
               |                     Wally Pipelined Core                    |
               |                        (RISC-V rv32i)                       |
               |                                                             |
               +------------------------------+------------------------------+
                                              |
                                        AHB-Lite Bus
                                              |
     +-----------------+----------------------+-------------------+--------------------+
     |                 |                                          |                    |
+----+----+       +----+----+                                +----+----+          +----+----+
|  Boot   |       | Unified |                                | AHB-to- |          | Internal|
|  ROM    |       |   RAM   |                                |   APB   |          |   AHB   |
|(0x1000) |       |(0x8000_)|                                | Bridge  |          |(0x3000_)|
|         |       |  0000   |                                |         |          |  0000   |
+---------+       +---------+                                +----+----+          +---------+
                                                                  |
                                                               APB Bus
                                                                  |
           +------------+------------+------------+---------------+---------------+
           |            |            |            |               |               |
      +----+----+  +----+----+  +----+----+  +----+----+     +----+----+     +----+----+
      |  UART   |  |  GPIO   |  |   SPI   |  |   SDC   |     |  CLINT  |     |  PLIC   |
      |(0x1000_)|  |(0x1006_)|  |(0x1004_)|  |(0x0A00_)|     |(0x0200_)|     |(0x0C00_)|
      |  0000   |  |  0000   |  |  0000   |  |  0000   |     |  0000   |     |  0000   |
      +---------+  +---------+  +---------+  +---------+     +---------+     +---------+
```

## Features

- **Pipelined RISC-V Core**: rv32i instruction set architecture with decoupled instruction and data caches.
- **AHB-Lite Interconnect**: Standardized bus interface to simplify attaching new IP blocks.
- **External Accelerator Support**: Dedicated AHB memory map region at `0x3000_0000` to plug in custom accelerators (e.g., Tsetlin Machine, Multiplier).
- **Unified RAM**: Mapped at `0x8000_0000` (`test.mem` initialization for simulation).
- **UART Output**: Memory-mapped UART peripheral at `0x1000_0000`.

## Memory Map

- `0x0000_1000`: Boot ROM
- `0x1000_0000`: UART (16550 compatible)
- `0x3000_0000`: External Accelerator AHB Slave Base
- `0x8000_0000`: Unified Memory (RAM / Main memory)

## Separated Data and Instruction Memory

In this architecture, instruction and data accesses are isolated within the core through dedicated **Instruction Cache (ICache)** and **Data Cache (DCache)** units. These caches interface with the Memory Management Unit (MMU) which subsequently arbitrates accesses across the shared AHB interconnect to the Unified RAM (`0x8000_0000`).

## Integrating an Accelerator

Custom accelerators are integrated directly into the SoC pipeline as **AHB Slaves**. The SoC internally routes an AHB interface dedicated specifically for this purpose.

1. **AHB Slave Interface**: Create a SystemVerilog module with an AHB slave interface (like `src/accelerator/multiplier_ahb.sv`).
2. **Integration**: Instantiate the module directly inside the core SoC wrapper (`src/wally/wallypipelinedsoc.sv`).
3. **Connecting Ports**: Connect the AHB slave ports to the SoC's internal `H*EXT` signals (e.g., `HRDATAEXT`, `HSELEXT`).
4. **Memory Address**: Access the accelerator in software using pointers to the base address `0x3000_0000`.

## Debug Unit

To add a debug unit:
1. Ensure the `DEBUG_SUPPORTED` configuration parameter in `config/config.vh` is enabled (set to `1`).
2. The core exposes JTAG Debug Module (DM) interfaces.
3. Map the DMI (Debug Module Interface) via the uncore to external pins to connect a JTAG adapter (e.g., OpenOCD).

## Simulation & Testing

The repository includes a streamlined simulation environment using **Verilator**.

### Compiling and Running C Code

1. Navigate to the `software/` directory.
2. Edit `main.c` to add your C program (ensure to read/write from `0x3000_0000` to interact with your accelerator).
3. From the **root** of the repository (`1tops_soc/`), simply run:

```bash
make test
```

This master script will:
- Clean and compile your `main.c` into a `test.mem` hex file.
- Clean and compile the Verilator hardware simulation model.
- Automatically execute the testbench simulation and print the C code outputs directly to your terminal.

> [!NOTE]
> **Full SoC Simulation**: Although the software prints output by directly addressing the accelerator (at `0x3000_000C`) for testing simplicity, the Verilator simulation includes the **entire Wally pipelined SoC**. All standard peripherals defined in `config.vh` (PLIC, CLINT, UART, GPIO, SPI, etc.) remain intact and fully simulated within the uncore.

## Viewing in Vivado

Since unnecessary build files have been stripped out, you can synthesize the RTL in Vivado by creating a new project and adding all `.sv` and `.vh` files located in the `src/` directory. Be sure to define the correct include directories in Vivado (e.g., `config/`, `src/wally/`, `src/generic/mem/`).
