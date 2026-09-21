# SoCDebug ASCII Debug Protocol (ADP) — Complete Command Reference

This document is a comprehensive cheatsheet of all commands supported by the **SoCDebug ADP Controller** (`socdebug_adp_control.v`) in `src/debugger/`.

All commands are case-insensitive (e.g., `a` or `A`, `r` or `R`) and must be terminated with a newline (`<ENTER>` / `\n` / `\r`).

---

## 1. Core Execution & System Control Commands

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Halt Core** | `C 0202` | Asserts bit 1 of GPO8 (`core_halt_o = 1` $\rightarrow$ `ExternalStall = 1`). Stalls all 5 pipeline stages. | `] C 0202`<br>`C 0x00020202` |
| **Resume Core** | `C 0102` | Clears bit 1 of GPO8 (`core_halt_o = 0` $\rightarrow$ `ExternalStall = 0`). Resumes pipeline execution. | `] C 0102`<br>`C 0x00000200` |
| **Assert Reset** | `C 0201` | Sets bit 0 of GPO8 (`core_reset_o = 1`). Holds CPU in reset. | `] C 0201`<br>`C 0x00010201` |
| **Release Reset** | `C 0101` | Clears bit 0 of GPO8 (`core_reset_o = 0`). Releases CPU reset. | `] C 0101`<br>`C 0x00000200` |
| **Overwrite GPO8** | `C 03<val8>` | Overwrites entire 8-bit GPO8 with `<val8>`. | `] C 0300`<br>`C 0x00000200` |
| **Query Status** | `C` | Reads current GPO8 outputs and GPI8 inputs without modifying them. | `] C`<br>`C 0x01000000` |
| **Enter ADP Mode** | `<ESC>` (`\x1b`) | Wakes up ADP command mode from idle/passthrough. | Press `ESC` key $\rightarrow$ displays `]` |
| **Exit ADP Mode** | `X` | Exits ADP monitor mode and switches serial channel to terminal/STDIO bypass. | `] X` |

---

## 2. Single-Word Memory & Peripheral Access

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Set Address** | `A <hex_addr>` | Sets internal AHB address pointer for subsequent operations. | `] A 30000008`<br>`A 0x30000008` |
| **Query Address** | `A` | Displays the current address pointer. | `] A`<br>`A 0x30000008` |
| **Read Word** | `R` | Reads 32-bit word from AHB at current address pointer, then auto-increments address (`addr += 4`). | `] R`<br>`R 0x0000002a` |
| **Read Multiple** | `R <count>` | Reads `<count>` consecutive words from memory, printing each on a new line and incrementing address. | `] R 4`<br>`R 0x12345678`<br>`R 0x00000042` ... |
| **Write Word** | `W <hex_val>` | Writes 32-bit word `<hex_val>` to current AHB address, then auto-increments address (`addr += 4`). | `] W 00000007`<br>`W 0x00000007` |

> **Bus Error Indicator (`!`)**: If an AHB bus error response (`HRESP = 1`) occurs during an `R` or `W` transaction, the response replaces the space with an exclamation mark:  
> `R!0x00000000` or `W!0xdeadbeef`.

---

## 3. Bulk Memory & High-Speed Operations

| Command | Syntax | Description | Example & Response |
| :--- | :--- | :--- | :--- |
| **Set Value** | `V <hex_val>` | Sets internal reference value register (`adp_val`). Used by Fill (`F`) and Poll (`P`) commands. | `] V deadbeef`<br>`V 0xdeadbeef` |
| **Fill Memory** | `F <count>` | Rapidly fills `<count>` words of memory starting at current address with the pattern set by `V`. | `] A 80000000`<br>`] V 00000000`<br>`] F 00000100` (zeroes 256 words) |
| **Binary Upload** | `U <count>` | Fast binary upload. Expects `<count>` raw binary bytes over UART and writes them sequentially into memory starting at address pointer. | `] A 80000000`<br>`] U 00000400`<br>*(stream raw bytes)* |

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

| Address Range | Region | Purpose |
| :--- | :--- | :--- |
| `0x3000_0000` | Dummy Multiplier Op A / CSR Ctrl | Accelerator operand A / Control |
| `0x3000_0004` | Dummy Multiplier Op B / CSR Status | Accelerator operand B / Status |
| `0x3000_0008` | Dummy Multiplier Product / Config | Accelerator product result (42) |
| `0x3000_000C` | Dummy Multiplier Print / Counters | Console character write |
| `0x3000_1000 - 0x300F_FFFF` | Accelerator Input Buffer | Feature activations (~1 MB) |
| `0x3010_0000 - 0x307F_FFFF` | Accelerator Weights Buffer | Model parameters / weights (~7 MB) |
| `0x3080_0000 - 0x30FF_FFFF` | Accelerator Output Buffer | Inference / results buffer (~8 MB) |
| `0x8000_0000` | SRAM / Main Memory | Program variables & memory |
