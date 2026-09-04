# 1TOPS SoC

A minimal RISC-V SoC based on the [CORE-V-Wally](https://github.com/openhwgroup/cvw) (CVW) processor, tailored for hardware synthesis and accelerator integration. The core runs a bare **rv32i** instruction set — FPU, caches, MDU, branch predictors, TLBs, and crypto/bitmanip extensions have all been stripped out to provide the smallest possible footprint for SoC generation.

## SoC Architecture

The SoC uses an **AHB-Lite** interconnect to connect the pipelined core, uncore peripherals, and a custom hardware accelerator.

```text
               +-------------------------------------------------------------+
               |                                                             |
               |                     RV32 Core                               |
               |                 (Minimal RISC-V rv32i)                      |
               |                                                             |
               +------------------------------+------------------------------+
                                              |
                                        AHB-Lite Bus
                                              |
     +-----------------+----------------------+-------------------+--------------------+
     |                 |                                          |                    |
+----+----+       +----+----+                                +----+----+          +----+----+
|  Boot   |       | Unified |                                | AHB-to- |          |Multiplier|
|  ROM    |       |   RAM   |                                |   APB   |          |  Accel.  |
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

## Memory Map

| Address          | Peripheral                   |
|------------------|------------------------------|
| `0x0000_1000`    | Boot ROM                     |
| `0x0200_0000`    | CLINT (Timer / SW Interrupts)|
| `0x0A00_0000`    | SDC (reserved)               |
| `0x0C00_0000`    | PLIC (Interrupt Controller)  |
| `0x1000_0000`    | UART (16550-compatible)      |
| `0x1004_0000`    | SPI                          |
| `0x1006_0000`    | GPIO                         |
| `0x3000_0000`    | Multiplier Accelerator (AHB) |
| `0x8000_0000`    | Unified RAM (Main Memory)    |

## Directory Structure

```
1tops_soc/
├── config/              # Configuration headers (config.vh, parameter-defs.vh)
├── schematics/          # Vivado project & TCL scripts for RTL schematic viewing
├── software/            # Bare-metal C test programs, linker script, startup code
│   ├── main.c           # Accelerator test program
│   ├── crt0.S           # Startup assembly
│   ├── link.ld          # Linker script
│   └── Makefile
├── src/                 # RTL source (SystemVerilog)
│   ├── accelerator/     # Custom AHB accelerators (multiplier_ahb.sv)
│   ├── ebu/             # External Bus Unit (AHB-Lite arbiter)
│   ├── generic/         # Flops, muxes, memories
│   ├── hazard/          # Pipeline hazard unit
│   ├── ieu/             # Integer Execution Unit (ALU, controller, regfile)
│   ├── ifu/             # Instruction Fetch Unit
│   ├── lsu/             # Load-Store Unit
│   ├── mmu/             # Memory Management Unit (address decoders, PMA/PMP)
│   ├── privileged/      # CSRs, trap handling, privilege modes
│   ├── uncore/          # SoC peripherals (UART, GPIO, SPI, CLINT, PLIC, RAM, ROM)
│   └── wally/           # Top-level SoC and core wrappers
├── testbench/           # Verilator testbench (tb.sv, sim_main.cpp)
├── filelist.f           # Verilator source file list
├── Makefile             # Top-level build: `make` compiles software + runs simulation
└── README.md
```

## Features

- **Pipelined RISC-V Core**: Minimal rv32i instruction set. No FPU, no caches, no MDU, no branch predictors, no TLBs, no compressed/crypto/bitmanip extensions.
- **AHB-Lite Interconnect**: Standard bus interface for attaching IP blocks.
- **External Accelerator Support**: Dedicated AHB region at `0x3000_0000` for custom accelerators (currently a hardware multiplier).
- **Full Uncore**: UART, GPIO, SPI, CLINT, PLIC, Boot ROM, and Unified RAM are all present and functional.
- **Unified RAM**: Mapped at `0x8000_0000`, initialized from `test.mem` during simulation.

## Integrating an Accelerator

Custom accelerators are integrated directly into the SoC as **AHB Slaves** inside the uncore module.

1. **Create an AHB Slave**: Write a SystemVerilog module with an AHB slave interface (see `src/accelerator/multiplier_ahb.sv` for reference).
2. **Instantiate in the Uncore**: Add the module inside `src/uncore/uncore.sv`, connecting to the internal `H*EXT` signals (`HRDATAEXT`, `HSELEXT`, etc.).
3. **Add to filelist**: Add the new `.sv` file path to `filelist.f`.
4. **Access from Software**: Use memory-mapped I/O at `0x3000_0000` in your C code.

### Multiplier Accelerator Registers

| Offset | Register | Description          |
|--------|----------|----------------------|
| `0x00` | OPA      | Operand A (write)    |
| `0x04` | OPB      | Operand B (write)    |
| `0x08` | RESULT   | Product A×B (read)   |
| `0x0C` | PRINT    | Debug char out (write)|

## Simulation & Testing

The repository includes a simulation environment using **Verilator**.

### Quick Start

From the root of the repository (`1tops_soc/`):

```bash
make
```

This single command will:
1. Clean and compile `software/main.c` into a `test.mem` hex file.
2. Clean and compile the Verilator hardware simulation model.
3. Execute the full SoC testbench and print C code outputs to your terminal.

> [!NOTE]
> **Full SoC Simulation**: The simulation includes the **entire Wally pipelined SoC** — all standard peripherals (PLIC, CLINT, UART, GPIO, SPI) remain intact and fully simulated within the uncore.

### Writing Your Own Test

1. Edit `software/main.c` with your C program.
2. Use `volatile uint32_t*` pointers to `0x3000_0000` to interact with the accelerator.
3. Run `make` from the repo root.

## Viewing RTL Schematics in Vivado

The `schematics/` directory includes scripts to visualize the RTL in Xilinx Vivado:

```bash
cd schematics
./open_vivado.sh
```

This creates a Vivado project, adds all sources, elaborates the RTL, and opens the schematic viewer. See `schematics/README.md` for details.
