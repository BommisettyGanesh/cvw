# Subsystem 02: Pipeline Hazard & Microarchitectural Stress Verification

## Overview
This subsystem exercises the microarchitectural behavior and corner cases of the 5-stage RISC-V pipelined core (`riscv_cpu`) integrated within the complete AHB/APB SoC. Rather than simple synthetic stimulus, these tests execute specifically engineered assembly stress routines that deliberately force worst-case hazards, mispredictions, trap redirections, and multi-cycle bus wait-states while formal SystemVerilog Assertions (SVA) run concurrently to guarantee microarchitectural safety.

---

## Test Cases Covered

1. **`hazard_forwarding_stress.S`**:
   * Stresses EX/MEM, MEM/WB, and WB/EX bypass forward paths across back-to-back dependent arithmetic instructions.
   * Exercises Load-Use data hazards (`lwStall`), verifying that Decode stage is stalled and Execute stage is flushed with zero data corruption.
2. **`branch_collision_stress.S`**:
   * Evaluates branch resolution in the Execute stage, testing taken vs not-taken branches, tight loops, and function call/returns (`jal`/`jalr`).
   * Validates that speculative instructions in the branch shadow are purged via `FlushD` and `FlushE`.
3. **`interrupt_trap_stress.S`**:
   * Configures the Core Local Interruptor (CLINT) timer (`mtimecmp`), enables Machine Timer Interrupts (`mie.MTIE`, `mstatus.MIE`).
   * Stresses precise trap entry, saving `mepc` and `mcause`, executing the ISR, and resuming cleanly with `mret`.
4. **`exception_trap_stress.S`**:
   * Tests synchronous exception handling for `ecall`, `ebreak`, and invalid/illegal opcodes.
5. **`subword_access_stress.S`**:
   * Stresses AHB byte write strobes (`HWSTRB`) and subword load alignments (`lb`, `lbu`, `lh`, `lhu`, `sw`, `sh`, `sb`) across unaligned byte addresses.
6. **`apb_bus_stress.S`**:
   * Fires continuous, back-to-back non-idle transfers across the AHB-to-APB bridge into GPIO, UART, and CLINT registers to verify wait-state insertion and protocol compliance.

---

## Formal Invariants & Assertions Monitored

The testbench continuously binds and executes 5 formal checker modules:
* [`core_invariants_checker.sv`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/02_pipeline_hazard_stress/assertions/core_invariants_checker.sv): Verifies PC word alignment, valid forwarding mux selects, trap vector redirection to `mtvec`, pipeline freeze on `ExternalStall`, and clean instruction retirement without stall/trap.
* [`ahb_protocol_checker.sv`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/02_pipeline_hazard_stress/assertions/ahb_protocol_checker.sv): Formally verifies AMBA 3 AHB-Lite bus rules (`HTRANS`, `HADDR`, `HWRITE` stability across wait states, non-overlap of slave select lines).
* [`apb_protocol_checker.sv`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/02_pipeline_hazard_stress/assertions/apb_protocol_checker.sv): Formally verifies AMBA APB state transitions (`IDLE` -> `SETUP` -> `ACCESS`).
* [`ramxdetector.sv`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/02_pipeline_hazard_stress/assertions/ramxdetector.sv): Detects and traps any `X` or uninitialized bit propagation.
* [`watchdog.sv`](file:///home/ganesh/Desktop/riscv/riscv_pipelined_quartus/final_tests/02_pipeline_hazard_stress/assertions/watchdog.sv): Detects livelocks, pipeline freezes, or infinite loops.

---

## How to Run the Tests

Execute from this directory:

```bash
# Run all 6 pipeline hazard stress tests
make test_all

# Run individual stress tests
make test_hazards          # Forwarding and load-use stalls
make test_branch_collision # Branch mispredictions & flushes
make test_interrupts       # CLINT timer interrupts & mret
make test_exceptions       # Traps: ecall, ebreak, illegal instruction
make test_subwords         # Subword access & byte strobes
make test_apb_stress       # Rapid APB bridge transactions

# Clean build artifacts
make clean
```
