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
rtlvisionpro -sv -top riscv_soc_ahb -f files.f &
```

---

## Design Hierarchy & Navigation in RTLvision PRO

When the GUI opens:
1. **Top Module:** Look at the Hierarchy Browser on the left for `riscv_soc_ahb` (from `1tops_soc/src2/main/soc/riscv_soc_ahb.v`).
2. **Subsystems to Explore:**
   - **`cpu` (`riscv_cpu`):** The 5-stage RISC-V pipelined processor core (`datapath`, `controller`, `hazard`, `csr_file`, and `reg_file` with non-intrusive debug read port).
   - **`u_core_debug_ahb` (`core_debug_ahb`):** Dedicated post-mortem AHB slave (`0x0B00_0000`) exposing GPRs `x0`–`x31`, pipeline stage PCs (`PCF`..`PCW`), privileged CSRs, 16-entry micro-trace FIFO, sticky crash trap registers, and hardware auto-halt trigger.
   - **`u_debugger` (`riscv_debugger_top`):** The dual-protocol (UART + FT1248) hardware debugger subsystem and AXI-stream multiplexer.
   - **`u_step_controller` (`core_step_controller`):** Single-step execution and hardware auto-halt on trap freeze controller.
   - **`u_ahb_mux` (`ahb_mux`):** 2-to-1 AHB bus arbiter granting priority to debugger.
   - **`u_uncore` (`uncore`):** Memory map decoder with `HSELCOREDBG` (`0x0B00_0000`), AHB-APB bridge, UART, GPIO, SPI, PLIC, CLINT, Boot ROM, and SRAMs.
   - **`u_accel` (`multiplier_ahb`):** The neural accelerator slave on the AHB bus.
3. **Signal Tracing:**
   - Right-click any signal or bus -> **Trace Fan-in (Cone of Logic)** or **Trace Fan-out** to see data paths.
   - Right-click submodules to generate FSM transition bubble diagrams (e.g. `core_step_controller` or `socdebug_adp_control`).
