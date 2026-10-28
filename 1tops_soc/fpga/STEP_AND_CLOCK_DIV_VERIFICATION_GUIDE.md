# Comprehensive Verification Guide: Core Step Execution & Clock Division

This document is the authoritative verification and engineering guide for two major enhancements to the **CORE-V Wally 1TOPS RISC-V SoC** and its **SoCDebug Dual-Protocol Hardware Debugger**:

1. **Hardware-Controlled Core Single-Step Execution** (`core_step_controller.sv`): Non-intrusive instruction-level and clock-cycle-level stepping with hardware retirement synchronization and watchdog protection.
2. **Reconfigurable In-Flight Clock Dividers** (`socdebug_uart.v` & `socdebug_ft1248_control.v`): Glitch-free dynamic clock divider reconfiguration for both the Debugger UART and FT1248 high-speed interfaces.

---

## 1. Architectural Design & Theory of Operation

```
                      +-------------------------------------------------------+
                      |                   Host Interface                      |
                      |          (HTerm / Minicom / dbg_cli.py / Python)      |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                   +-------------------------------------------------------------+
                   |                 Protocol Stream Multiplexer                 |
                   |               (dbg_sel: 0 = UART, 1 = FT1248)               |
                   +------------------------------+------------------------------+
                                                  |
                                                  v
                   +-------------------------------------------------------------+
                   |         SoCDebug ASCII Debug Protocol (ADP) Controller       |
                   |                  (socdebug_adp_control.v)                   |
                   +---------------+-----------------------------+---------------+
                                   |                             |
                                   | GPO8[3:2] (Step Mode/Req)   | Clock Dividers
                                   | GPI8[2:1] (Step Done/Busy)  | (B / D Commands)
                                   v                             v
+------------------------------------+   +---------------------------------------+
|     core_step_controller.sv        |   |   Reconfigurable Clock Divider Regs   |
|                                    |   |                                       |
|  - STATE_RUN                       |   |  - UART 16-bit Register (clks_per_bit)|
|  - STATE_HALTED                    |   |    Latches ONLY when RX & TX are IDLE |
|  - STATE_STEPPING                  |   |  - FT1248 8-bit Register (ft_clkdiv)  |
|  - STATE_DONE                      |   +---------------------------------------+
|  - Watchdog Counter (65,536 cycles)|                                   |
+-----------------+------------------+                                   |
                  |                                                      v
                  | core_stall_effective                   +----------------------------+
                  v (ExternalStall)                        | Dedicated Transceivers     |
+------------------------------------+                     | - socdebug_uart.v          |
|      wallypipelinedcore.sv         |                     | - socdebug_ft1248_control.v|
|                                    |                     +----------------------------+
|  - 5-Stage Hazard Unit Stalled     |
|  - InstrRetired Feedback:          |
|    InstrValidM & ~StallW & ~FlushW |
+------------------------------------+
```

### A. Core Step Controller FSM (`core_step_controller.sv`)
The step controller arbitrates the CPU pipeline stall signal (`core_stall_effective` $\rightarrow$ `ExternalStall`):
- **`STATE_RUN`**: When `halt_req_i = 0`, the core runs free; `core_stall_effective` reflects normal external stalls.
- **`STATE_HALTED`**: When `halt_req_i = 1`, `core_stall_effective` is asserted high, freezing all 5 pipeline stages (Fetch, Decode, Execute, Memory, Writeback).
- **`STATE_STEPPING`**: Triggered by a rising edge on `step_req_i` (`GPO8[2] = 1`). `core_stall_effective` is momentarily released (pulled low), allowing the pipeline to clock forward.
  - **Instruction Step Mode (`step_mode_i = 0`)**: The core runs until `instr_retired_i` pulses high (indicating that an instruction successfully reached and retired in the Writeback stage) OR until the 16-bit watchdog timer reaches 65,535 cycles.
  - **Clock Cycle Step Mode (`step_mode_i = 1`)**: The core runs for **exactly 1 clock cycle**, advancing the pipeline by 1 tick regardless of whether an instruction retired.
- **`STATE_DONE`**: The step controller immediately re-asserts `core_stall_effective = 1`, pulses `step_done_o = 1` for 1 clock cycle, increments internal `step_count_o`, and transitions back to `STATE_HALTED`.

### B. Glitch-Free Clock Divider Reconfiguration
- **UART Transceiver (`socdebug_uart.v`)**:
  - The 16-bit `clks_per_bit_reg` register controls the baud rate timing.
  - **Glitch-Free Guarantee**: It is updated *strictly* when both the RX engine and TX engine are completely idle (`rx_state == RX_IDLE && tx_state == TX_IDLE && !s_axis_tvalid`). This ensures that character transmission, command echoes, and framing bits are never corrupted mid-byte when switching speeds.
  - Clamped to a minimum divisor of 4 cycles to eliminate zero/single-cycle division lockups.
- **FT1248 Transceiver (`socdebug_ft1248_control.v`)**:
  - Driven by the 8-bit `ft_clkdiv` register.
  - FT1248 serial clock output is generated as: $\text{SCLK} = \frac{f_{\text{CLK}}}{2 \times (\text{DIV} + 1)}$.

---

## 2. Command Reference & Protocol Grammar

All commands are terminated with `<ENTER>` (`\r` or `\n`).

### Boot & Status Commands
| Command | Syntax | Response | Description |
| :--- | :--- | :--- | :--- |
| **Boot Prompt** | *(automatic)* | ` 0x50c1ab04\r\n]` | Controller auto-enters ADP command mode on boot/reset. **No ESC character is required.** |
| **Query Status** | `C` | `C 0x<GPI8><GPO8>0000` | Reads control register (`GPO8`) and status register (`GPI8`). |
| **Halt Core** | `C 0202` | `C 0x01020000` | Sets `GPO8[1] = 1` (`core_halt_o = 1`). Freezes CPU pipeline. LED 0 turns ON. |
| **Resume Core** | `C 0102` | `C 0x00000000` | Clears `GPO8[1] = 0` (`core_halt_o = 0`). Resumes free execution. LED 0 turns OFF. |
| **Assert Reset**| `C 0201` | `C 0x01030000` | Sets `GPO8[0] = 1` (`core_reset_o = 1`). Holds core in reset. |
| **Release Reset**| `C 0101` | `C 0x01020000` | Clears `GPO8[0] = 0` (`core_reset_o = 0`). Core stays halted at reset vector. |

### Step Execution Commands
| Step Mode | Assert Trigger | Clear Trigger | Description |
| :--- | :--- | :--- | :--- |
| **Instruction Step** | `C 0204` | `C 0104` | Sets `GPO8[2] = 1`, mode = 0. Releases stall until **1 instruction commits**, then re-freezes core. |
| **Clock-Cycle Step** | `C 020c` | `C 010c` | Sets `GPO8[2] = 1`, `GPO8[3] = 1`. Releases stall for **exactly 1 clock cycle**, then re-freezes core. |

#### Hardware Bit Mapping (`C` Response: `C 0x<GPI8><GPO8>0000`)
- **`GPI8` Status Register (Read-Only)**:
  - `Bit 0` (`0x01`): **Core Halted** (1 = CPU halted by debugger).
  - `Bit 1` (`0x02`): **Step Busy** (1 = Step in flight).
  - `Bit 2` (`0x04`): **Step Done** (1-cycle pulse upon completion).
  - `Bit 3` (`0x08`): **`dbg_trap_latched`** (1 = Unhandled exception / crash latched by hardware).
  - `Bit 4` (`0x10`): **`IllegalInstrD`** (Illegal opcode fault flag).
  - `Bit 5` (`0x20`): **`MisalignD`** (Misaligned branch/jump fault flag).
  - `Bit 6` (`0x40`): **`MemFaultM`** (Memory/bus fault flag).
  - `Bit 7` (`0x80`): **`TrapM`** (Dynamic active trap pulse).
- **`GPO8` Control Register (Read/Write)**:
  - `Bit 0` (`0x01`): Core Reset Request.
  - `Bit 1` (`0x02`): Core Halt Request (`ExternalStall`).
  - `Bit 2` (`0x04`): Core Step Trigger (rising edge initiated).
  - `Bit 3` (`0x08`): Step Mode Select (0 = Instruction Step, 1 = Clock-Cycle Step).

---

### Reconfigurable Clock Divider Commands (`B` & `D`)
| Command | Syntax | Example Response | Description |
| :--- | :--- | :--- | :--- |
| **Query Dividers** | `B` | `B 0x000101b2` | Queries both UART (bits 15:0) and FT1248 (bits 23:16) dividers. |
| **Set UART Divider** | `B <hex16>` | `B 0x000400d9` | Sets 16-bit UART clock divider (clocks per bit). |
| **Set UART Explicitly** | `B 01<hex16>` | `B 0x0004006d` | Subcommand 01: Sets UART baud divider. |
| **Set FT1248 Explicitly** | `B 020000<hex8>` | `B 0x000201b2` | Subcommand 02: Sets 8-bit FT1248 divider. |
| **Set Both Dividers** | `B 03<uart16><ft8>` | `B 0x00010036` | Subcommand 03: Sets UART divider (`uart16`) and FT1248 divider (`ft8`). |
| **Query FT1248 Divider**| `D` | `D 0x01` | Queries 8-bit FT1248 clock divider (returns 0x01 on FPGA, 0x04 on ASIC). |
| **Set FT1248 Divider** | `D <hex8>` | `D 0x08` | Sets 8-bit FT1248 clock divider. |

---

## 3. Clock Divisor & Baud Rate Reference Tables

### A. 50 MHz FPGA Clock (Digilent Basys 3)
On Basys 3, the 100 MHz oscillator is scaled by on-chip MMCM to $f_{\text{CLK}} = 50\text{ MHz}$.

$$\text{UART Divider} = \text{round}\left(\frac{50{,}000{,}000}{\text{Baud Rate}}\right)$$

| Target Baud Rate | Clock Cycles / Bit (Dec) | Divider Hex (`B <hex>`) | Actual Baud Rate | Error % |
| :--- | :---: | :---: | :---: | :---: |
| **115,200 Baud** *(Default)* | `434` | `0x01B2` | 115,207 | +0.006% |
| **230,400 Baud** | `217` | `0x00D9` | 230,415 | +0.006% |
| **460,800 Baud** | `109` | `0x006D` | 458,716 | -0.45% |
| **921,600 Baud** | `54` | `0x0036` | 925,926 | +0.47% |
| **1,500,000 Baud** | `33` | `0x0021` | 1,515,152 | +1.01% |
| **3,000,000 Baud** | `17` | `0x0011` | 2,941,176 | -1.96% |

#### FT1248 SCLK Rates at 50 MHz:
$$\text{SCLK} = \frac{50\text{ MHz}}{2 \times (\text{DIV} + 1)}$$
- `DIV = 1` (`D 01`): $\text{SCLK} = 12.5\text{ MHz}$
- `DIV = 2` (`D 02`): $\text{SCLK} = 8.33\text{ MHz}$
- `DIV = 4` (`D 04`): $\text{SCLK} = 5.00\text{ MHz}$ *(Default)*
- `DIV = 8` (`D 08`): $\text{SCLK} = 2.78\text{ MHz}$

---

### B. 100 MHz ASIC / Simulation Clock
$$\text{UART Divider} = \text{round}\left(\frac{100{,}000{,}000}{\text{Baud Rate}}\right)$$

| Target Baud Rate | Clock Cycles / Bit (Dec) | Divider Hex (`B <hex>`) |
| :--- | :---: | :---: |
| **115,200 Baud** *(Default)* | `868` | `0x0364` |
| **230,400 Baud** | `434` | `0x01B2` |
| **460,800 Baud** | `217` | `0x00D9` |
| **921,600 Baud** | `109` | `0x006D` |
| **1,500,000 Baud** | `67` | `0x0043` |
| **3,000,000 Baud** | `33` | `0x0021` |

---

## 4. Verification Method 1: Automated RTL Simulation (Vivado XSIM)

We have provided a one-click automated simulation script that compiles all SystemVerilog modules and runs the comprehensive testbench (`tb/tb_debugger.sv`):

```bash
cd 1tops_soc/fpga
./sim_step_and_clkdiv.sh
```

### What this Testbench Validates:
1. **Startup Banner & Auto-Prompt**: Verifies prompt `]` arrives automatically on UART.
2. **UART Read/Write Accesses**: Tests IRAM, DRAM, and 1TOPS Accelerator access over UART.
3. **FT1248 Read/Write Accesses**: Switches `dbg_sel = 1` and verifies high-speed bus transfers.
4. **Stream Mux Isolation**: Verifies UART cannot inject commands when `dbg_sel = 1`.
5. **Core Step FSM Verification (Part 4)**:
   - Halts core (`C 0202`).
   - Executes single instruction step (`C 0204` / `C 0104`); verifies pipeline advances and re-freezes.
   - Executes clock-cycle step (`C 020c` / `C 010c`); verifies 1-cycle execution.
   - Resumes core (`C 0102`).
6. **Clock Divider Verification (Part 5)**:
   - Queries default dividers (`B` and `D`).
   - Updates FT1248 divider to 8 (`D 08`).
   - Updates UART divider to 40 cycles (`B 0028`), adjusts testbench bit period, and verifies live bidirectional communication at the new baud rate.
   - Restores dividers via `B 03001402`.
   - Reconfigures FT1248 divider over the FT1248 bus interface.

**Expected Simulation Summary:**
```text
===============================================================================
   ALL DUAL-PROTOCOL TEST SCENARIOS COMPLETED!
   Passed Assertions: 26
   Failed Assertions: 0
===============================================================================
>>> [SUCCESS] ALL UART, FT1248, AND MUX ISOLATION TESTS PASSED! <<<
```

---

## 5. Verification Method 2: Automated Python Test Suite

The repository includes `test_step_and_clkdiv.py`, a self-checking test script supporting both physical FPGA hardware and an in-memory emulator:

### A. Run in Mock Mode (No FPGA Hardware Required)
```bash
cd 1tops_soc/fpga
python3 test_step_and_clkdiv.py --mock
```

### B. Run Against Real Hardware (Basys 3)
Ensure the board is connected via USB and set `SW0` Down (`dbg_sel = 0`):
```bash
cd 1tops_soc/fpga
python3 test_step_and_clkdiv.py --protocol uart --device /dev/ttyUSB0 --baud 115200
```

### C. Run Specific Test Subsets
```bash
# Test only instruction and cycle stepping:
python3 test_step_and_clkdiv.py --mock --test step

# Test only UART and FT1248 clock dividers:
python3 test_step_and_clkdiv.py --mock --test clkdiv
```

**Sample Output:**
```text
==============================================================================
 FINAL VERIFICATION SUMMARY
==============================================================================
  Passed Assertions: 16
  Failed Assertions: 0

>>> [SUCCESS] ALL TEST SCENARIOS PASSED CLEANLY! <<<
```

---

## 6. Verification Method 3: Manual Interactive Stepping Walkthrough (HTerm)

Configure HTerm with **115200 Baud, 8 Data Bits, 1 Stop Bit, No Parity, Send on Enter = `CR`**.

### Step 1: Verify Direct Auto-Prompt on Boot
1. Press center pushbutton `btnC` (or power cycle).
2. The terminal displays:
   ```text
    0x50c1ab04
   ]
   ```
   LED 15 on Pin L1 immediately turns solidly ON.

### Step 2: Halt CPU and Load `step_test.bin`
1. Freeze CPU pipeline:
   ```text
   C 0202
   ```
   *(LED 0 turns ON).*
2. Clear Data RAM locations `0x80002000`–`0x80002010`:
   ```text
   A 80002000
   V 00000000
   F 08
   ```
3. Upload `step_test.bin` (64 bytes = `0x40` bytes):
   ```text
   A 80000000
   U 40
   ```
   In HTerm, click **Send File**, select `1tops_soc/fpga/step_test.bin`.  
   Board replies: `U 0x00000040` followed by `]`.

4. Reset PC to `0x80000000` while keeping core halted:
   ```text
   C 0201
   C 0101
   ```

### Step 3: Perform Single-Instruction Steps & Observe DRAM
1. Trigger Instruction Step:
   ```text
   C 0204
   C 0104
   ```
2. Repeat `C 0204` / `C 0104` four times (advancing past `lui s0`, `li t0`, and `sw t0, 0(s0)`).
3. Read Data RAM at `0x80002000`:
   ```text
   A 80002000
   R
   ```
   **Expected Response:** `R 0x11111111`.

4. Perform 3 more instruction steps:
   ```text
   C 0204
   C 0104
   C 0204
   C 0104
   C 0204
   C 0104
   ```
5. Read Data RAM at `0x80002004`:
   ```text
   A 80002004
   R
   ```
   **Expected Response:** `R 0x22222222`.

6. Perform 3 more steps and verify `0x80002008`:
   ```text
   A 80002008
   R
   ```
   **Expected Response:** `R 0x33333333`.

### Step 4: Resume Core
```text
C 0102
```
*(LED 0 turns OFF; CPU resumes free execution).*

---

## 7. Verification Method 4: Live Baud Rate Switching in HTerm

1. Check current clock dividers:
   ```text
   B
   ```
   Reply at 50 MHz: `B 0x000101b2` (UART = 434 cycles = 115,200 baud, FT1248 = 1 for 12.5 MHz).

2. Reconfigure UART to **230,400 Baud** (`217` cycles = `0x00D9`):
   ```text
   B 00d9
   ```
   Reply: `B 0x000400d9`.

3. In HTerm, disconnect, change baud rate setting to **`230400`**, and click **Connect**.
4. Press `<ENTER>` or type:
   ```text
   B
   ```
   Reply: `B 0x000400d9`.  
   *(Bidirectional communication is verified at 230,400 baud!)*

5. Restore **115,200 Baud** (`434` cycles = `0x01B2`):
   ```text
   B 01b2
   ```
6. In HTerm, disconnect, set baud rate back to **`115200`**, and reconnect. Send `B` to confirm normal operation.

---

## 8. Verification Method 5: Post-Mortem Crash Debugging & Core Inspection (`0x0B00_0000`)

The **Core Debug AHB Slave** (`core_debug_ahb.v`) exposes internal processor pipeline registers, register file, privileged CSRs, and execution history directly onto the AHB bus at base address `0x0B00_0000`.

### 8.1 Register Map (`Base: 0x0B00_0000`)
- `0x000` – `0x07C`: General-Purpose Registers `x0` – `x31` (readout via non-intrusive auxiliary port).
- `0x080` – `0x090`: Stage Program Counters (`PCF`, `PCD`, `PCE`, `PCM`, `PCW`).
- `0x094` – `0x098`: Active instruction words in Decode and Memory stages (`InstrD`, `InstrM`).
- `0x09C`: Pipeline Status (`{StallFlags[4:0], FlushFlags[4:0]}`).
- `0x0A0` – `0x0CC`: Privileged CSRs (`mstatus`, `mcause`, `mtval`, `mepc`, `mtvec`, `mie`, `mip`, `mscratch`, cycle and instret counters).
- `0x0D0`: `DBG_CTRL` (Bit 0 = auto-halt enable, Bit 1 = clear sticky crash trap).
- `0x0D4`: `TRAP_CAUSE` (Sticky latched exception cause at crash).
- `0x0D8`: `TRAP_VAL` (Sticky latched trap value / faulting address / opcode).
- `0x0DC`: `TRAP_PC` (Sticky latched Program Counter of faulting instruction).
- `0x100` – `0x13C`: 16-entry Circular Micro-Trace Buffer (last 16 retired instruction PCs).
- `0x140`: Micro-Trace Status (`{wrap_flag, write_ptr[3:0]}`).

### 8.2 Testing via Python Automated Test Suite
Run the dedicated post-mortem verification suite in mock mode:
```bash
python3 test_step_and_clkdiv.py --mock --test postmortem
```
Or run all tests:
```bash
python3 test_step_and_clkdiv.py --mock --test all
```

### 8.3 Post-Mortem Analysis in Serial Terminal (ADP Commands)
1. **Detect Crash via Status Query (`C`)**:
   ```text
   C
   ```
   If a crash occurred, `GPI8` returns `0x19` (`Bit 0` = Halted, `Bit 3` = Trap Latched, `Bit 4` = Illegal Instruction).
2. **Inspect Faulting Instruction & PC**:
   ```text
   A 0B0000D4
   R
   A 0B0000DC
   R
   ```
   Returns latched `mcause` (e.g. `0x00000002` for illegal instruction) and exact faulting `PC` (e.g. `0x80000014`).
3. **Dump Register File (`x0` – `x31`) in one burst**:
   ```text
   A 0B000000
   R 00000020
   ```
4. **Inspect Last 16 Committed Program Counters**:
   ```text
   A 0B000100
   R 00000010
   ```
5. **Clear Crash Latch**:
   ```text
   A 0B0000D0
   W 00000003
   ```

---

## 9. Summary of Files & Tools

| File Path | Description |
| :--- | :--- |
| [`../src2/debugger/core_debug_ahb.v`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/core_debug_ahb.v) | Post-mortem AHB slave exposing GPRs, CSRs, micro-trace & crash latches |
| [`../src2/debugger/core_step_controller.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/core_step_controller.sv) | Hardware Step FSM controller with `auto_halt_req_i` freeze on trap |
| [`../src2/debugger/socdebug_adp_control.v`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/socdebug_adp_control.v) | ADP controller with `B`, `D`, and step GPO/GPI extensions |
| [`../src2/debugger/socdebug_uart.v`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/socdebug_uart.v) | Glitch-free reconfigurable UART baud divider engine |
| [`../src2/debugger/socdebug_ft1248_control.v`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/socdebug_ft1248_control.v) | Reconfigurable FT1248 clock divider |
| [`../src2/debugger/tb/tb_debugger.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/tb/tb_debugger.sv) | Self-checking simulation testbench (Parts 4 & 5) |
| [`../src2/debugger/sw/dbg_cli.py`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src2/debugger/sw/dbg_cli.py) | Python CLI supporting `step`, `step_cycle`, `get_dividers`, etc. |
| [`test_step_and_clkdiv.py`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/test_step_and_clkdiv.py) | Automated Python test runner with Test Suite 4 for post-mortem debugging |
| [`sim_step_and_clkdiv.sh`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/sim_step_and_clkdiv.sh) | Automated Vivado XSIM simulation script |
| [`../software/step_test.S`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/software/step_test.S) | Dedicated RV32I assembly stepping verification program |
| [`step_test.bin`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/fpga/step_test.bin) | Compiled 64-byte machine code for single-step verification |
