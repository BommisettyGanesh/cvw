# 1TOPS SoC

A minimal RISC-V SoC based on the [CORE-V-Wally](https://github.com/openhwgroup/cvw) (CVW) processor, tailored for hardware synthesis and accelerator integration. The core runs a bare **rv32i** instruction set — FPU, caches, MDU, branch predictors, TLBs, and crypto/bitmanip extensions have all been stripped out to provide the smallest possible footprint for SoC generation.

## SoC Architecture

The SoC uses an **AHB-Lite** interconnect to connect the pipelined core, uncore peripherals, and a custom hardware accelerator.

```text
                                +-------------------------------------------------------+
                                |                                                       |
                                |                       RV32 Core                       |
                                |                 (Minimal RISC-V rv32i)                |
                                |                                                       |
                                +---------------------------+---------------------------+
                                                            |
                                                      AHB-Lite Bus
                                                            |
          +-------------------------+-----------------------+-----------------------+-------------------------+
          |                         |                       |                       |                         |
  +-------+-------+         +-------+-------+       +-------+-------+       +-------+-------+         +-------+-------+
  |   Boot ROM    |         |   Instr RAM   |       |   Data RAM    |       |  AHB-to-APB   |         |  Multiplier   |
  |    (4 KB)     |         |    (8 KB)     |       |    (8 KB)     |       |    Bridge     |         |    (16 MB)    |
  +---------------+         +---------------+       +---------------+       +-------+-------+         +---------------+
                                                                                    |
                                                                                 APB Bus
                                                                                    |
        +-----------------------+-----------------------+---------------------------+---------------------------+-----------------------+
        |                       |                       |                           |                           |                       |
+-------+-------+       +-------+-------+       +-------+-------+           +-------+-------+           +-------+-------+       +-------+-------+
|     UART      |       |     GPIO      |       |      SPI      |           |      SDC      |           |     CLINT     |       |     PLIC      |
|     (8 B)     |       |    (256 B)    |       |    (4 KB)     |           |    (4 KB)     |           |    (64 KB)    |       |    (64 MB)    |
+---------------+       +---------------+       +---------------+           +---------------+           +---------------+       +---------------+
```

## Memory Map

| Start Address | End Address   | Size   | Bus | Peripheral                   |
|---------------|---------------|--------|-----|------------------------------|
| `0x0000_1000` | `0x0000_1FFF` | 4 KB   | AHB | Boot ROM                     |
| `0x0200_0000` | `0x0200_FFFF` | 64 KB  | APB | CLINT (Timer / SW Interrupts)|
| `0x0A00_0000` | `0x0A00_0FFF` | 4 KB   | APB | SDC (Debug Unit / Reserved)  |
| `0x0C00_0000` | `0x0FFF_FFFF` | 64 MB  | APB | PLIC (Interrupt Controller)  |
| `0x1000_0000` | `0x1000_0007` | 8 B    | APB | UART (16550-compatible)      |
| `0x1004_0000` | `0x1004_0FFF` | 4 KB   | APB | SPI                          |
| `0x1006_0000` | `0x1006_00FF` | 256 B  | APB | GPIO                         |
| `0x3000_0000` | `0x30FF_FFFF` | 16 MB  | AHB | Multiplier Accelerator       |
| `0x8000_0000` | `0x8000_1FFF` | 8 KB   | AHB | Instruction RAM              |
| `0x8000_2000` | `0x8000_3FFF` | 8 KB   | AHB | Data RAM                     |

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
- **Full Uncore**: UART, GPIO, SPI, CLINT, PLIC, Boot ROM, and Independent Instruction/Data RAMs are all present and functional.
- **Independent RAMs**: 16KB total, mapped at `0x8000_0000` (8KB Instruction RAM) and `0x8000_2000` (8KB Data RAM), initialized from `test_instr.mem` and `test_data.mem` during simulation.

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
1. Clean and compile `software/main.c` into `test_instr.mem` and `test_data.mem` hex files.
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
- `link.ld`: A minimal linker script mapping code to the Instruction RAM and data to the Data RAM.
- `crt0.S`: Assembly startup script to initialize the stack and jump to `main`.
- `Makefile`: Uses `riscv64-unknown-elf-gcc` to compile the C files and generates `test_instr.mem` and `test_data.mem` hex files.

### 2. Simulating with Verilator (`testbench/`)
The `testbench/` directory contains a complete simulation environment.

**Prerequisites:**
You need `verilator` and `riscv64-unknown-elf-gcc` installed on your machine.

**Running the Simulation:**
Navigate to the testbench directory and run `make run` (or just `make` from the repository root):
```bash
make
```

**What happens when you type `make`:**
1. It builds the Verilator C++ model of `tb.sv` (which includes the SoC and the Accelerator).
2. It copies the `software/test_instr.mem` and `software/test_data.mem` (your compiled C code) into the testbench directory.
3. It runs the simulation. The internal `ram_ahb.sv` memory modules use `$readmemh` to preload your C code into the Instruction and Data SRAMs.
4. The simulation executes, and a `trace.vcd` waveform is generated (limited to AHB signals to reduce size) for debugging in GTKWave!
