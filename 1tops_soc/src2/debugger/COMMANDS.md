# SoCDebug ASCII Debug Protocol (ADP) — Complete Command Reference

This document is a comprehensive cheatsheet of all commands supported by the **SoCDebug ADP Controller** (`socdebug_adp_control.v`) in `src/debugger/`.

All commands are case-insensitive (e.g., `a` or `A`, `r` or `R`) and must be terminated with a newline (`<ENTER>` / `\n` / `\r`).

---

## 0. Physical Protocol Interface Selection (`dbg_sel` Pin) & Status LEDs

The debugger subsystem features a physical hardware input pad, **`dbg_sel`** (Slide Switch SW0 on Basys 3), controlling a 2-to-1 stream multiplexer between external interfaces:

| `dbg_sel` Pad Level | Active Physical Interface | Physical Pins Used | Transfer Characteristics |
| :---: | :--- | :--- | :--- |
| **`0` (LOW)** | **Dedicated Debug UART** | `uart_rx` (J1), `uart_tx` (L2) | Asynchronous 8-N-1 (Default 115200 Baud). Simple standard serial terminal (HTerm) or USB-to-UART dongle. |
| **`1` (HIGH)** | **Dedicated FT1248 Interface** | `ft1248_clk` (A14), `ft1248_ss_n` (A16), `ft1248_miso` (B15), `ft1248_miosio` (B16) | Synchronous serial/nibble/byte bus with FTDI FT232H / FT2232H. High-speed transfers up to 30 MHz. |

### Visual Feedback LEDs (Basys 3)
- **LED 0 (`led_core_halted` on Pin U16)**: Lit when CPU core is halted by debugger (`ExternalStall = 1`).
- **LED 1 (`led_dbg_sel` on Pin E19)**: Lit when FT1248 mode is selected (`SW0 = 1`).
- **LED 15 (`led_rx_detect` on Pin L1)**: 
  - **Activity Pulse**: Blinks for ~200 ms upon receiving any valid UART byte.
  - **Prompt Lock**: Latches solidly ON upon receiving/transmitting the prompt character `]` (`0x5D`), confirming command mode.

> [!IMPORTANT]
> The ADP command grammar, syntax, responses, and state machines are **100% identical** across both UART and FT1248 modes. When `dbg_sel = 1`, the UART interface is electrically isolated; conversely, when `dbg_sel = 0`, the FT1248 interface is isolated.

---

## 1. Core Execution & System Control Commands

### Startup & Direct Auto-Entry
- **Direct Auto-Prompt on Boot**: On power-on or board reset (`btnC`), the controller sends ` 0x50c1ab04\r\n`, auto-enters ADP command mode, outputs the prompt character `]`, and latches LED 15 ON. **No escape character (`0x1B`) is required!**
- **Exit Command Mode (`X` / `Ctrl+D`)**: Type `X` (or send `0x04`) to leave ADP monitor mode and switch to terminal/STDIO passthrough if desired.
- **Re-enter Command Mode (`<ESC>` / `0x1B`)**: If in passthrough mode, send `<ESC>` (`\x1b`) to re-enter ADP command mode.

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Halt Core** | `C 0202` | Asserts bit 1 of GPO8 (`core_halt_o = 1` -> `ExternalStall = 1`). Stalls all 5 pipeline stages. LED 0 turns ON. | `] C 0202`<br>`C 0x00020202` |
| **Resume Core** | `C 0102` | Clears bit 1 of GPO8 (`core_halt_o = 0` -> `ExternalStall = 0`). Resumes pipeline execution. LED 0 turns OFF. | `] C 0102`<br>`C 0x00000200` |
| **Instruction Step** | `C 0204`<br>`C 0104` | Asserts bit 2 of GPO8 (`step_req = 1`, mode = 0). Releases stall until **1 instruction commits** in pipeline, then auto-freezes core. Cleared via `C 0104`. | `] C 0204`<br>`C 0x00060204`<br>`] C 0104` |
| **Clock-Cycle Step** | `C 020c`<br>`C 010c` | Asserts bits 2 & 3 of GPO8 (`step_req = 1`, mode = 1). Releases stall for **exactly 1 clock cycle**, then auto-freezes core. Cleared via `C 010c`. | `] C 020c`<br>`C 0x000e020c`<br>`] C 010c` |
| **Assert Reset** | `C 0201` | Sets bit 0 of GPO8 (`core_reset_o = 1`). Holds CPU in reset. | `] C 0201`<br>`C 0x00010201` |
| **Release Reset** | `C 0101` | Clears bit 0 of GPO8 (`core_reset_o = 0`). Releases CPU reset. | `] C 0101`<br>`C 0x00000200` |
| **Overwrite GPO8** | `C 03<val8>` | Overwrites entire 8-bit GPO8 with `<val8>`. | `] C 0300`<br>`C 0x00000200` |
| **Query Status** | `C` | Reads current GPO8 outputs and GPI8 inputs without modifying them. Bit 0 = Halted, Bit 1 = Step Busy, Bit 2 = Step Done. | `] C`<br>`C 0x01000000` |
| **Enter ADP Mode** | `<ESC>` (`\x1b`) | Wakes up ADP command mode from idle/passthrough. | Send `1B` (HEX) -> displays `]` |
| **Exit ADP Mode** | `X` | Exits ADP monitor mode and switches serial channel to terminal/STDIO bypass. | `] X` |

---

## 2. Single-Word Memory & Peripheral Access

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Set Address** | `A <hex_addr>` | Sets internal AHB address pointer for subsequent operations. | `] A 30000008`<br>`A 0x30000008` |
| **Query Address** | `A` | Displays the current address pointer. | `] A`<br>`A 0x30000008` |
| **Read Word** | `R` | Reads 32-bit word from AHB at current address pointer, then auto-increments address (`addr += 4`). | `] R`<br>`R 0x00000078` |
| **Read Multiple** | `R <count>` | Reads `<count>` items from memory. **Access size is derived from digit count**: 1-2 digits = bytes, 4 digits = halfwords, 8 digits = words. | `] R 4` (reads 4 bytes)<br>`] R 00000004` (reads 4 words) |
| **Write Word** | `W <hex_val>` | Writes 32-bit word `<hex_val>` to current AHB address, then auto-increments address (`addr += 4`). | `] W 00000007`<br>`W 0x00000007` |

> [!NOTE]
> **Parameter Sizing for `R` & `W`**:
> - **Plain `R` (no parameter)**: Defaults to **32-bit Word** read (`HSIZE = 3'b010`). Prints 8 hex digits `R 0xXXXXXXXX` and increments address by 4.
> - **`R 4` (1 or 2 hex digits)**: Encodes **8-bit Byte** read (`HSIZE = 3'b000`). Prints 4 separate lines of 1 byte each (`R 0xXX`), incrementing address by 1 byte per line (which displays 1 word broken into 4 bytes).
> - **`R 0004` (4 hex digits)**: Encodes **16-bit Halfword** read (`HSIZE = 3'b001`). Prints 4 halfwords (`R 0xXXXX`), incrementing address by 2 bytes each.
> - **`R 00000004` (8 hex digits)**: Encodes **32-bit Word** read (`HSIZE = 3'b010`). Prints 4 words (`R 0xXXXXXXXX`), incrementing address by 4 bytes each.

> **Bus Error Indicator (`!`)**: If an AHB bus error response (`HRESP = 1`) occurs during an `R` or `W` transaction, the response replaces the space with an exclamation mark:  
> `R!0x00000000` or `W!0xdeadbeef`.

---

## 3. Reconfigurable Clock Divider Commands (`B` & `D`)

The hardware debugger incorporates internal configuration registers for both the **UART baud rate divider** (16-bit) and **FT1248 clock divider** (8-bit). These registers are completely isolated from the RISC-V core and can **only be read and written by the debugger**.

* **Power-On Reset Defaults**:
  * **ASIC**: UART = 868 (`0x0364` for 100 MHz / 115200 baud), FT1248 = 4 (`0x04` for 10 MHz).
  * **FPGA**: UART = 434 (`0x01B2` for 50 MHz / 115200 baud), FT1248 = 1 (`0x01` for 12.5 MHz on Basys 3 FPGA top).
* **Glitch-Free Guarantee**: The UART divider register only updates when both RX and TX engines are completely idle (`rx_state == RX_IDLE && tx_state == TX_IDLE`), guaranteeing that command echo/response bytes and framing are never corrupted mid-flight.

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Query Dividers** | `B` | Queries both UART (low 16 bits) and FT1248 (middle 8 bits) dividers. Format: `0x00<FT_DIV8><UART_DIV16>`. | `] B`<br>`B 0x00040364` (ASIC default)<br>`B 0x000401B2` (FPGA default) |
| **Set UART Baud Divider** | `B <hex16>` | Configures the UART clock divider (clocks per bit). | `] B 006d`<br>`B 0x0004006d` (sets 921,600 baud at 100MHz) |
| **Set UART Divider Explicitly** | `B 01<hex16>` | Subcommand `01`: Explicitly sets the 16-bit UART clock divider. | `] B 010364`<br>`B 0x00040364` |
| **Set FT1248 Divider Explicitly** | `B 02<hex8>` | Subcommand `02`: Explicitly sets the 8-bit FT1248 clock divider. | `] B 020008`<br>`B 0x00080364` |
| **Set Both Dividers** | `B 03<uart16><ft8>` | Subcommand `03`: Simultaneously sets UART divider (middle 16 bits) and FT1248 divider (low 8 bits). | `] B 03006d01`<br>`B 0x0001006d` (UART 921.6k, FT1248 25MHz) |
| **Query FT1248 Divider** | `D` | Queries only the 8-bit FT1248 clock divider. | `] D`<br>`D 0x01` (FPGA default)<br>`D 0x04` (ASIC default) |
| **Set FT1248 Divider** | `D <hex8>` | Sets the 8-bit FT1248 clock divider. | `] D 01`<br>`D 0x01` (sets 25 MHz on 100MHz ASIC) |

### Common Baud Rate Divider Table

| Desired Baud Rate | 100 MHz ASIC Divider (Dec / Hex) | 50 MHz FPGA Divider (Dec / Hex) |
| :--- | :--- | :--- |
| **115,200 Baud** *(Default)* | `868` (`0x0364`) | `434` (`0x01B2`) |
| **230,400 Baud** | `434` (`0x01B2`) | `217` (`0x00D9`) |
| **460,800 Baud** | `217` (`0x00D9`) | `109` (`0x006D`) |
| **921,600 Baud** | `109` (`0x006D`) | `54` (`0x0036`) |
| **1,500,000 Baud** | `67` (`0x0043`) | `33` (`0x0021`) |
| **3,000,000 Baud** | `33` (`0x0021`) | `17` (`0x0011`) |

---

## 4. Bulk Memory & High-Speed Operations

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Set Value** | `V <hex_val>` | Sets internal reference value register (`adp_val`). Used by Fill (`F`) and Poll (`P`) commands. | `] V deadbeef`<br>`V 0xdeadbeef` |
| **Fill Memory** | `F <count>` | Rapidly fills `<count>` words of memory starting at current address with the pattern set by `V`. `<count>` is in hexadecimal 32-bit words. | `] A 80000000`<br>`] V 00000000`<br>`] F 200`<br>`F 0x00000200` (zeroes 512 words / 2 KB) |
| **Binary Upload** | `U <count>` | Fast byte stream upload. Expects `<count>` raw binary bytes over UART and writes them sequentially into memory starting at address pointer. `<count>` is in hexadecimal bytes. | `] A 80000000`<br>`] U 4c`<br>*(stream 76 raw bytes)*<br>`U 0x0000004c` |

### Detailed Binary Upload (`U`) Procedure:
1. **Set target address**: `A <hex_addr>` (e.g. `A 80000000` for instruction memory).
2. **Issue upload command**: `U <hex_byte_count>` (e.g. `U 4c` for 76 bytes).
3. **Stream raw binary data**:
   - In **HTerm**: Click **Send File**, select your `.bin` file, and send as raw binary.
   - In **Python**: Send `file.read()` directly to the serial port.
4. **Subword Strobe Decoding (`HWSTRB`)**:
   `wallypipelinedsoc.sv` decodes `dbg_HWSTRB` from `HSIZE` and `HADDR[1:0]`. Byte writes only activate the targeted byte lane in memory, safely writing consecutive bytes without corrupting neighboring memory bytes.
5. **Completion**: The board acknowledges with `U 0x000000<count>\r\n]` and returns to command mode.

---

## 4. Hardware Polling & Status Synchronization

Used to wait for hardware accelerator completion (e.g. busy bit clearing) without CPU intervention:

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Set Mask** | `M <hex_mask>` | Sets comparison bitmask (`adp_mask`). Only bits set to `1` in the mask will be tested by `P`. | `] M 00000001`<br>`M 0x00000001` (test bit 0 only) |
| **Set Match Value** | `V <hex_val>` | Sets target expected value after masking: `(read_data & mask) == val`. | `] V 00000000`<br>`V 0x00000000` (wait for bit 0 == 0) |
| **Poll Hardware** | `P <timeout>` | Repeatedly reads current AHB address until `(HRDATA & mask) == val`, or until `<timeout>` cycles expire. | `] A 30000004`<br>`] P 0000ffff`<br>`P 0x00000042` (matched after 66 cycles) |

---

## 5. Console & STDIN Injection

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Inject STDIN** | `S <hex_char>` | Injects an 8-bit character into the processor's UART/STDIN receive FIFO (if STDIN bus enabled). | `] S 0a` (sends Enter/newline) |

---

## 6. Access Size Encoding

The debugger automatically adjusts AHB transfer size (`HSIZE` = byte, halfword, or word) depending on parameter formatting:
- Standard 8-digit hex parameters default to **32-bit Word** transfers (`HSIZE = 3'b010`).
- 4-digit parameters trigger **16-bit Halfword** transfers (`HSIZE = 3'b001`).
- 2-digit parameters trigger **8-bit Byte** transfers (`HSIZE = 3'b000`).

---

## 7. Memory Map Quick Reference (CORE-V Wally)

| Address Range | Size | Region | Purpose |
| :--- | :--- | :--- | :--- |
| `0x0000_1000 - 0x0000_1FFF` | 4 KB | Boot ROM | Initial boot code |
| `0x0B00_0000 - 0x0B00_0FFF` | 4 KB | Core Debug & Post-Mortem | CPU GPRs (x0-x31), CSRs, Trace Buffer & Crash Trap Registers |
| `0x1000_0000 - 0x1000_0007` | 8 B | 16550 Uncore UART | Application printf/console UART |
| `0x3000_0000` | 4 B | Multiplier Op A | Accelerator operand A / Control |
| `0x3000_0004` | 4 B | Multiplier Op B | Accelerator operand B / Status |
| `0x3000_0008` | 4 B | Multiplier Product | Accelerator product result |
| `0x3000_000C` | 4 B | Multiplier Print | Console character write |
| `0x3000_1000 - 0x300F_FFFF` | ~1 MB | Accelerator Input Buffer | Feature activations |
| `0x3010_0000 - 0x307F_FFFF` | ~7 MB | Accelerator Weights Buffer | Model parameters / weights |
| `0x3080_0000 - 0x30FF_FFFF` | ~8 MB | Accelerator Output Buffer | Inference / results buffer |
| `0x8000_0000 - 0x8000_1FFF` | 8 KB | Instruction SRAM (`ram_i`) | Program code (reset vector) |
| `0x8000_2000 - 0x8000_3FFF` | 8 KB | Data SRAM (`ram_d`) | Program data, heap, and stack |

---

## 8. Post-Mortem Crash Debugging & Core Inspection (`0x0B00_0000` Aperture)

The **Core Debug AHB Slave** (`core_debug_ahb.v`) exposes the internal state of the RISC-V CPU pipeline, privileged control registers (CSRs), register file, and execution history directly onto the AHB bus at base address `0x0B00_0000`.

### 8.1 Register Map (`Base: 0x0B00_0000`)

| Offset Range | Register Name | Access | Description |
| :--- | :--- | :---: | :--- |
| `0x000 - 0x07C` | `GPR[0]` - `GPR[31]` | R | **General-Purpose Registers `x0` - `x31`**: Directly read from regfile auxiliary port without disturbing pipeline. |
| `0x080` | `PC_FETCH` (`PCF`) | R | Program Counter currently in Instruction Fetch stage |
| `0x084` | `PC_DECODE` (`PCD`) | R | Program Counter currently in Instruction Decode stage |
| `0x088` | `PC_EXECUTE` (`PCE`) | R | Program Counter currently in Execute / ALU stage |
| `0x08C` | `PC_MEMORY` (`PCM`) | R | Program Counter currently in Memory access stage |
| `0x090` | `PC_WRITEBACK` (`PCW`) | R | Last committed Program Counter retiring from Writeback stage |
| `0x094` | `INSTR_DECODE` (`InstrD`) | R | Raw 32-bit instruction word currently in Decode stage |
| `0x098` | `INSTR_MEMORY` (`InstrM`) | R | Raw 32-bit instruction word currently in Memory stage |
| `0x09C` | `PIPELINE_STATUS` | R | Pipeline Hazard Status: `[9:5]` = `StallFlags[4:0]`, `[4:0]` = `FlushFlags[4:0]` |
| `0x0A0` | `CSR_MSTATUS` | R | Machine Status CSR (`mstatus`) |
| `0x0A4` | `CSR_MCAUSE` | R | Machine Cause CSR (`mcause`) — dynamic current value |
| `0x0A8` | `CSR_MTVAL` | R | Machine Trap Value CSR (`mtval`) — dynamic current value |
| `0x0AC` | `CSR_MEPC` | R | Machine Exception Program Counter CSR (`mepc`) |
| `0x0B0` | `CSR_MTVEC` | R | Machine Trap-Vector Base-Address CSR (`mtvec`) |
| `0x0B4` | `CSR_MIE` | R | Machine Interrupt Enable CSR (`mie`) |
| `0x0B8` | `CSR_MIP` | R | Machine Interrupt Pending CSR (`mip`) |
| `0x0BC` | `CSR_MSCRATCH` | R | Machine Scratchpad CSR (`mscratch`) |
| `0x0C0` | `CYCLE_LOW` | R | 64-bit Hardware Cycle Counter [31:0] |
| `0x0C4` | `CYCLE_HIGH` | R | 64-bit Hardware Cycle Counter [63:32] |
| `0x0C8` | `INSTRET_LOW` | R | 64-bit Retired Instruction Counter [31:0] |
| `0x0CC` | `INSTRET_HIGH` | R | 64-bit Retired Instruction Counter [63:32] |
| `0x0D0` | `DBG_CTRL` | R/W | Control Register:<br/>- Bit 0: `auto_halt_en` (1 = freeze core upon trap, default 1)<br/>- Bit 1: `trap_clr` (write 1 to clear sticky crash latches) |
| `0x0D4` | `TRAP_CAUSE` | R | **Sticky Latched Crash Cause**: Captures `mcause` at the exact cycle of exception |
| `0x0D8` | `TRAP_VAL` | R | **Sticky Latched Fault Value**: Captures `mtval` (faulting address or illegal instruction) |
| `0x0DC` | `TRAP_PC` | R | **Sticky Latched Faulting PC**: Captures `PCM` (PC of instruction that caused the trap) |
| `0x100 - 0x13C` | `TRACE_BUF[0..15]` | R | **16-Entry Circular Micro-Trace Buffer**: Contains the last 16 retired instruction PCs prior to crash |
| `0x140` | `TRACE_STATUS` | R | Trace Buffer Status: `[4]` = `wrap_flag`, `[3:0]` = `write_pointer` |

---

### 8.2 Real-Time Crash Detection via Status Query (`C`)

The debugger controller continuously samples CPU status flags into `GPI8`:
- **`GPI8[0]`**: `core_halted` (1 when pipeline is frozen)
- **`GPI8[1]`**: `step_busy` (1 when single-step sequence is active)
- **`GPI8[2]`**: `step_done` (1 when step completed)
- **`GPI8[3]`**: **`dbg_trap_latched`** (1 indicates an unhandled trap/crash occurred and crash registers are frozen)
- **`GPI8[4]`**: `IllegalInstrD` (fault flag: illegal opcode decoded)
- **`GPI8[5]`**: `MisalignD` (fault flag: misaligned jump/branch)
- **`GPI8[6]`**: `MemFaultM` (fault flag: bus/memory access fault)
- **`GPI8[7]`**: `TrapM` (dynamic active trap signal)

Querying status via `C` immediately flags crashes:
```
] C
C 0x19000000
```
*(Here `GPI8 = 0x19`: Bit 0 = Halted, Bit 3 = Trap Latched, Bit 4 = Illegal Instruction).*

---

### 8.3 Post-Mortem Crash Analysis Workflow via ADP

When the target crashes or stops unexpectedly, follow this sequence using standard ADP commands:

#### Step 1: Confirm Crash & Check Latched Cause
```
] C
C 0x19000000       <-- Core is halted and trap is latched (0x19 = 8'b00011001)

] A 0B0000D4       <-- Point to TRAP_CAUSE
A 0x0B0000D4
] R                <-- Read latched mcause
R 0x00000002       <-- mcause = 2: Illegal Instruction Exception!

] A 0B0000DC       <-- Point to TRAP_PC
A 0x0B0000DC
] R                <-- Read latched faulting PC
R 0x80000014       <-- Crash occurred at address 0x8000_0014
```

#### Step 2: Inspect Register File State (All 32 Registers)
Dump all 32 GPRs in one burst using `R 00000020` (32 words):
```
] A 0B000000       <-- Base of GPR table (x0)
A 0x0B000000
] R 00000020       <-- Read 32 words (x0 through x31)
R 0x00000000       <-- x0  (always 0)
R 0x0000000a       <-- x1  (e.g., 10)
R 0x00000014       <-- x2  (e.g., 20)
R 0x0000001e       <-- x3  (e.g., 30)
...
R 0x80003ff0       <-- x2 (sp)
```

#### Step 3: Inspect Pipeline Registers and Opcodes
```
] A 0B000080       <-- Point to PC_FETCH
A 0x0B000080
] R 00000008       <-- Read 8 words: PCF, PCD, PCE, PCM, PCW, InstrD, InstrM, PipelineStatus
R 0x8000001c       <-- PCF
R 0x80000018       <-- PCD
R 0x80000014       <-- PCE
R 0x80000014       <-- PCM (Faulting instruction stage)
R 0x80000010       <-- PCW (Last successfully retired instruction)
R 0x00200073       <-- InstrD (Offending opcode in decode)
R 0x00200073       <-- InstrM (Offending opcode in memory stage)
R 0x000003e0       <-- PipelineStatus: StallFlags=5'b11111 (all stages frozen)
```

#### Step 4: Inspect 16-Entry Micro-Trace Buffer (Pre-Crash History)
Read the last 16 committed Program Counters prior to the crash to observe control flow path:
```
] A 0B000100       <-- Point to Micro-Trace Buffer
A 0x0B000100
] R 00000010       <-- Read 16 words (trace history)
R 0x80000000       <-- PC history entry 0
R 0x80000004       <-- PC history entry 1
R 0x80000008       <-- PC history entry 2
R 0x8000000c       <-- PC history entry 3
R 0x80000010       <-- PC history entry 4 (last commit before crash)
...
```

#### Step 5: Clear Trap and Re-arm
To clear the latched trap and reset the sticky registers:
```
] A 0B0000D0       <-- DBG_CTRL register
A 0x0B0000D0
] W 00000003       <-- Assert trap_clr (bit 1) and keep auto_halt_en (bit 0)
W 0x00000003
```
After clearing, the core can be reset via `C 0201` / `C 0101` or resumed via `C 0102`.

