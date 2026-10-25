# RTLvision PRO Schematic Viewer for 1TOPS SoC

This directory contains the setup, filelist, and launcher script to view the entire **CORE-V Wally RV32 SoC + Neural Accelerator** schematic using **RTLvision PRO**.

---

## Prerequisites & Environment Modules

The module available on this system is:
```bash
module load altairdsim/RTLvisionPRO/2025.1
```
*(Note: Version `2025.1` has a valid, active license on the server).*

---

## How to View the Entire SoC

From this directory (`1tops_soc/rtlvision`), simply run:

```bash
./open_rtlvision.sh
```

Or manually:
```bash
module load altairdsim/RTLvisionPRO/2025.1
rtlvisionpro -sv -top wallypipelinedsocwrapper -f files.f &
```

---

## Design Hierarchy & Navigation in RTLvision PRO

When the GUI opens:
1. **Top Module:** Look at the Hierarchy Browser on the left for `wallypipelinedsocwrapper` -> `soc` (`wallypipelinedsoc`).
2. **Subsystems to Explore:**
   - **`core` (`wallypipelinedcore`):** The 5-stage RISC-V pipelined core (`ifu`, `ieu`, `lsu`, `mmu`, `hazard`, `privileged`).
   - **`uncore`:** AHB-APB bridge, UART, GPIO, SPI, PLIC, CLINT, Boot ROM, and RAM.
   - **`accel` (`multiplier_ahb`):** The neural accelerator slave on the AHB bus.
   - **`u_debugger` (`riscv_debugger_top`):** The UART / FT1248 debugger subsystem and `ahb_mux`.
3. **Signal Tracing:**
   - Right-click any signal or bus -> **Trace Fan-in (Cone of Logic)** or **Trace Fan-out** to see data paths.
   - Right-click submodules to generate FSM transition bubble diagrams.
