# Subsystem 04: AMBA AHB/APB Bus Fabric & Arbiter Verification

This subsystem contains constrained-random and directed verification testbenches for the AMBA bus interconnect architecture of the pipelined RISC-V SoC.

---

## 1. Subsystem Architecture Overview

The SoC bus fabric consists of:
1. **2-Master AHB-Lite Arbiter / Multiplexer ([ahb_mux.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/debugger/ahb_mux.sv))**:
   - Arbitrates between **Master 0 (CPU Core)** and **Master 1 (Debugger Host)**.
   - Pipelined grant tracking (`grant_addr` for address phase, `grant_data` for data phase).
   - Priority arbitration: When both masters contend simultaneously, Master 1 (Debugger) is granted priority.
   - `core_halt` override: When the CPU core is halted, debugger transactions take complete precedence without starvation.
2. **AHB-to-APB Bridge ([ahbapbbridge.sv](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/uncore/ahbapbbridge.sv))**:
   - Converts pipelined AHB-Lite transfers into two-phase APB3 transfers (`SETUP` cycle followed by `ACCESS` cycle with `PENABLE`).
   - Dynamic wait-state stretching (`PREADY` pulling `HREADYOUT` low).
   - Address decoding and read data multiplexing across APB peripherals (UART, GPIO, CLINT, PLIC).

---

## 2. Testbenches

### A. 2-Master AHB Arbiter Verification (`tb/tb_ahb_mux_crv.sv`)
- **TEST 1 (Uncontended CPU M0 Transfers)**: Runs 20 randomized AHB transactions driven exclusively by Master 0, checking address translation, data routing, and writeback to slave memory.
- **TEST 2 (Uncontended Debugger M1 Transfers)**: Runs 20 randomized AHB transactions driven exclusively by Master 1, verifying that the debugger can independently read/write system memory.
- **TEST 3 (Simultaneous Contention & Priority)**: Asserts simultaneous valid transfer requests from Master 0 and Master 1 on the exact same clock cycles. Verifies that Master 1 (Debugger) wins 100% of arbitration contention without deadlock.
- **TEST 4 (Core Halt Mode)**: Asserts `core_halt = 1` and verifies that Master 1 achieves immediate single-cycle access to downstream peripherals and commits writes accurately.

### B. AHB-to-APB Bridge Verification (`tb/tb_ahb_apb_bridge_crv.sv`)
- **TEST 1 (Zero-Wait State Write)**: Verifies that during the setup cycle, `PSEL` asserts, `PENABLE` remains low, and `HREADYOUT` holds low, transitioning on the next cycle to `PENABLE = 1` and `HREADYOUT = 1`.
- **TEST 2 (Zero-Wait State Read)**: Verifies peripheral read multiplexing and propagation of read data back to `HRDATA`.
- **TEST 3 (Multi-Wait State Write)**: Injects 2 wait states (`PREADY = 0` for 2 cycles). Verifies that `PENABLE` stays high, `PADDR` and `PWDATA` remain stable, and `HREADYOUT` stays low until `PREADY` asserts.
- **TEST 4 (Multi-Wait State Read)**: Injects 3 wait states, verifying read data hold and proper bus release.
- **TEST 5 (50-Iteration Constrained-Random Suite)**: Randomizes peripheral target (0 to 3), addresses, 32-bit payloads, read/write direction, and 0-3 wait states.

---

## 3. How to Run

From this directory:

```bash
# Run all bus fabric tests
make test_all

# Run individual tests
make test_ahb_mux
make test_apb_bridge

# Clean build artifacts
make clean
```

All tests recompile libraries fresh (`rm -rf work && vlib work && vlog ...`) before simulation.
