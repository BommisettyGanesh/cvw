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
  * **FPGA**: UART = 434 (`0x01B2` for 50 MHz / 115200 baud), FT1248 = 4 (`0x04` for 5 MHz).
* **Glitch-Free Guarantee**: The UART divider register only updates when both RX and TX engines are completely idle (`rx_state == RX_IDLE && tx_state == TX_IDLE`), guaranteeing that command echo/response bytes and framing are never corrupted mid-flight.

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Query Dividers** | `B` | Queries both UART (low 16 bits) and FT1248 (middle 8 bits) dividers. Format: `0x00<FT_DIV8><UART_DIV16>`. | `] B`<br>`B 0x00040364` (ASIC default)<br>`B 0x000401B2` (FPGA default) |
| **Set UART Baud Divider** | `B <hex16>` | Configures the UART clock divider (clocks per bit). | `] B 006d`<br>`B 0x0004006d` (sets 921,600 baud at 100MHz) |
| **Set UART Divider Explicitly** | `B 01<hex16>` | Subcommand `01`: Explicitly sets the 16-bit UART clock divider. | `] B 010364`<br>`B 0x00040364` |
| **Set FT1248 Divider Explicitly** | `B 02<hex8>` | Subcommand `02`: Explicitly sets the 8-bit FT1248 clock divider. | `] B 020008`<br>`B 0x00080364` |
| **Set Both Dividers** | `B 03<uart16><ft8>` | Subcommand `03`: Simultaneously sets UART divider (middle 16 bits) and FT1248 divider (low 8 bits). | `] B 03006d01`<br>`B 0x0001006d` (UART 921.6k, FT1248 25MHz) |
| **Query FT1248 Divider** | `D` | Queries only the 8-bit FT1248 clock divider. | `] D`<br>`D 0x04` |
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
