# CORE-V Wally RISC-V SoC: Complete Debugger Wiring Architecture & Signal Specification

This specification provides the exhaustive, pin-by-pin wiring connection map for the **SoCDebug hardware debugger subsystem** within the **CORE-V Wally RISC-V SoC** (`1tops_soc`). It covers all interconnects from the external physical UART lines (`UARTSin`, `UARTSout`), through the shared Uncore 16550-compatible UART transceiver and ASCII Debug Protocol (ADP) controller, to the RISC-V CPU pipeline hazard unit, the 2-master AHB-Lite bus arbiter/mux, the uncore address decoder, and all target memory/peripheral slaves.

---

## 1. High-Resolution Architecture Schematic

![CORE-V Wally RISC-V SoC Debugger Full Wiring Architecture](/home/23EC01043/.gemini/antigravity-ide/brain/2c997c37-ebc3-4325-a562-c7741fc79680/debugger_wiring_diagram.png)

> [!NOTE]
> - **Workspace Copy (PNG)**: [`debugger_wiring_diagram.png`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/debugger_wiring_diagram.png)
> - **Vector Copy (Scalable SVG)**: [`debugger_wiring_diagram.svg`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/debugger_wiring_diagram.svg)
> - **Artifact Copy**: [`debugger_wiring_diagram.png`](file:///home/23EC01043/.gemini/antigravity-ide/brain/2c997c37-ebc3-4325-a562-c7741fc79680/debugger_wiring_diagram.png)

---

## 2. Top-Level Subsystem Block Hierarchy

```mermaid
graph TD
    classDef host fill:#1e293b,stroke:#0f172a,color:#fff
    classDef uart fill:#581c87,stroke:#6b21a8,color:#fff
    classDef adp fill:#1d4ed8,stroke:#1e3a8a,color:#fff
    classDef core fill:#b45309,stroke:#92400e,color:#fff
    classDef hazard fill:#b91c1c,stroke:#991b1b,color:#fff
    classDef mux fill:#0f766e,stroke:#115e59,color:#fff
    classDef uncore fill:#6b21a8,stroke:#581c87,color:#fff
    classDef slave fill:#065f46,stroke:#064e3b,color:#fff

    subgraph Host["Host PC / Workstation"]
        CLI["Python CLI / Serial Terminal<br/>(dbg_cli.py @ 115200 Baud)"]:::host
    end

    subgraph UncoreSub["Uncore Subsystem: uncore.sv"]
        UART["Uncore 16550 UART<br/>uartPC16550D.sv / uart_apb.sv<br/>Base: 0x1001_3000"]:::uart
        DEC["Address Decoder (adrdecs.sv)<br/>Delay Register (hseldelayreg)"]:::uncore
        RMUX["HRDATA / HREADY / HRESP<br/>Read Multiplexer & Gating"]:::uncore
    end

    subgraph DbgSub["Debugger Subsystem: riscv_debugger_top.sv"]
        ADP["ADP Protocol & AHB Master<br/>socdebug_ahb.v / socdebug_adp_control.v"]:::adp
    end

    subgraph CPU["RISC-V CPU: wallypipelinedcore.sv"]
        PIPE["5-Stage Pipeline<br/>(IF, ID, EX, MEM, WB)"]:::core
        HAZ["Hazard Unit<br/>hazard.sv"]:::hazard
    end

    subgraph BusMux["Bus Arbiter & Mux: ahb_mux.sv"]
        MUX["2-to-1 AHB-Lite Arbiter<br/>Pipelined grant_addr / grant_data"]:::mux
    end

    subgraph Slaves["Target Slaves & Memories"]
        ACC["1TOPS Accelerator / Multiplier<br/>0x30000000 - 0x30FFFFFF"]:::slave
        IRAM["Instruction SRAM (ram_i)<br/>0x80000000 (8 KB)"]:::slave
        DRAM["Data SRAM (ram_d)<br/>0x80002000 (8 KB)"]:::slave
        ROM["Boot ROM (bootrom)<br/>0x00010000 (64 KB)"]:::slave
        APB["AHB-to-APB Bridge & Peripherals<br/>CLINT, PLIC, GPIO, SPI, SDC"]:::slave
    end

    CLI -->|UARTSin (Physical RX)| UART
    UART -->|UARTSout (Physical TX)| CLI

    UART -->|dbg_uart_rx_data/valid/ready| ADP
    ADP -->|dbg_uart_tx_data/valid/ready| UART

    ADP -->|core_halt_o| HAZ
    ADP -->|core_halt_o (priority)| MUX
    ADP -->|core_reset_o| CPU
    HAZ -->|core_halted_status| ADP

    HAZ -->|StallF..W = 1| PIPE

    PIPE -->|Master 0 (core_h*)| MUX
    ADP -->|Master 1 (DEBUG_*)| MUX

    MUX -->|Downstream AHB (S_*)| DEC
    DEC -->|HSELEXT| ACC
    DEC -->|HSELRam| IRAM
    DEC -->|HSELDRAM| DRAM
    DEC -->|HSELBootRom| ROM
    DEC -->|HSELBRIDGE| APB

    ACC -->|HRDATAEXT / HREADYEXT| RMUX
    IRAM -->|HREADRam / HREADYRamI| RMUX
    DRAM -->|HREADSDC / HREADYRamD| RMUX
    ROM -->|HREADBootRom / HREADYBootRom| RMUX
    APB -->|HREADBRIDGE / HREADYBRIDGE| RMUX

    RMUX -->|S_HRDATA / S_HREADY / S_HRESP| MUX
    MUX -->|M0_HRDATA / HREADY| PIPE
    MUX -->|M1_HRDATA / HREADY| ADP
```

---

## 3. Exhaustive Pin-by-Pin Wiring Specifications

### Group 1: External Physical Interface (Host PC ↔ SoC Physical UART Pins)

The redesigned architecture eliminates duplicate standalone UART transceivers by reusing the SoC's primary 16550-compatible UART in `uncore`. Only a single pair of physical UART pins is required for the entire SoC to support both application console prints and hardware debugging.

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `UARTSin` | 1 | Input | External Pin / USB-UART TX | `wallypipelinedsoc.UARTSin` $\rightarrow$ `uncore.UARTSin` $\rightarrow$ `uartPC16550D.Sin` | Serial command ingress from user terminal / Python CLI. | Receives asynchronous serial ASCII characters at 115200 baud (8 data bits, no parity, 1 stop bit). Fed into 2-FF metastability synchronizer. Broadcasts to both CPU APB receiver and Debugger RX stream. |
| `UARTSout` | 1 | Output | `uartPC16550D.Sout` $\rightarrow$ `uncore.UARTSout` $\rightarrow$ `wallypipelinedsoc.UARTSout` | External Pin / USB-UART RX | Response egress back to host terminal / Python CLI. | Serializes ADP text responses (e.g. read register values, command prompts `]`, error alerts `!`) or CPU printfs at 115200 baud. Driven idle-high (`1'b1`). Debugger egress has priority when active. |
| `clk` (`HCLK`) | 1 | Input | System Clock Generator / PLL | All Submodules (`HCLK`) | Synchronous clock reference across entire SoC. | Primary 50.0 MHz clock driving UART baud counter, ADP state machine, pipeline stages, and AHB bus transfers. |
| `rst_n` (`HRESETn`) | 1 | Input | Reset Controller / Button | All Submodules (`HRESETn` / `reset_n`) | Safe global system initialization. | Active-low reset synchronized through a 2-stage DFF to prevent release race conditions. Flushes state machines to IDLE. |

---

### Group 2: Internal Debugger Streams (`uncore.sv`'s `uartPC16550D` ↔ `riscv_debugger_top.sv`)

The 16550 UART transceiver converts physical serial bits into parallel 8-bit bytes and connects directly to the ASCII Debug Protocol engine over internal streaming handshake channels:

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `dbg_uart_rx_data[7:0]` | 8 | Internal | `uncore.dbg_uart_rx_data[7:0]` (`uartPC16550D.dbg_rx_data`) | `u_debugger.uart_rx_data[7:0]` $\rightarrow$ `u_adp.COMRX_TDATA_i[7:0]` | Character data payload from serial receiver to protocol engine. | Carries deserialized 8-bit ASCII characters (e.g. `'A'`, `'R'`, `'W'`, `'C'`, digits `'0'`-`'9'`, `'A'`-`'F'`, and `'\n'`). |
| `dbg_uart_rx_valid` | 1 | Internal | `uncore.dbg_uart_rx_valid` (`uartPC16550D.dbg_rx_valid`) | `u_debugger.uart_rx_valid` $\rightarrow$ `u_adp.COMRX_TVALID_i` | Data transfer strobe. | Pulses HIGH when UART stop bit is confirmed and `rxbuf` contains a valid incoming ASCII character (`rxstate == UART_DONE`). |
| `dbg_uart_rx_ready` | 1 | Internal | `u_debugger.uart_rx_ready` $\leftarrow$ `u_adp.COMRX_TREADY_o` | `uncore.dbg_uart_rx_ready` (`uartPC16550D.dbg_rx_ready`) | Ingress flow control / backpressure. | Driven HIGH by ADP when FSM is ready to consume the next character. Handshake completes when `valid && ready`. |
| `dbg_uart_tx_data[7:0]` | 8 | Internal | `u_debugger.uart_tx_data[7:0]` $\leftarrow$ `u_adp.COMTX_TDATA_o[7:0]` | `uncore.dbg_uart_tx_data[7:0]` (`uartPC16550D.dbg_tx_data`) | Character data payload from protocol engine to serial transmitter. | Carries 8-bit ASCII characters generated by ADP (banner characters, hex data bytes, prompt `]`, spaces, and newlines). |
| `dbg_uart_tx_valid` | 1 | Internal | `u_debugger.uart_tx_valid` $\leftarrow$ `u_adp.COMTX_TVALID_o` | `uncore.dbg_uart_tx_valid` (`uartPC16550D.dbg_tx_valid`) | Egress transfer strobe. | Asserted by ADP when a response character is ready to be serialized and sent to the host PC. Directly loads UART TX shift register. |
| `dbg_uart_tx_ready` | 1 | Internal | `uncore.dbg_uart_tx_ready` (`uartPC16550D.dbg_tx_ready`) | `u_debugger.uart_tx_ready` $\rightarrow$ `u_adp.COMTX_TREADY_i` | Egress backpressure from UART. | Driven HIGH only when UART TX state machine is ready (`txstate == UART_DONE || txstate == UART_START` with no ongoing transmission). Holds ADP FSM until serialization finishes. |

---

### Group 3: Core Control & Status Interface (Debugger ↔ RISC-V Core & Hazard Unit)

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `core_halt_o` | 1 | Output | `u_adp.GPO8_o[1]` (`u_debugger.core_halt_o`) | 1. `wallypipelinedcore.ExternalStall`<br/>2. `ahb_mux.core_halt` | **The Master Hardware Pause Button.** Freezes CPU and switches bus mastership. | When host sends `C 0202`, bit 1 of `GPO8` is set to `1`. This directly asserts `ExternalStall` in [`hazard.sv`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/hazard/hazard.sv#L34-L95), forcing `StallF = StallD = StallE = StallM = StallW = 1`. All 5 stages freeze in place without pipeline flushing. Simultaneously tells `ahb_mux` to give 100% bus priority to Debugger. |
| `core_halted_i` | 1 | Input | `wallypipelinedcore.ExternalStall` feedback | `u_debugger.core_halted_i` $\rightarrow$ `u_adp.GPI8_i[0]` | Pipeline halt status feedback to host. | Mapped to bit 0 of `GPI8` register inside [`socdebug_ahb.v`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/socdebug_ahb.v#L68). When host sends query command `C`, bit 0 reflects `1` if core is safely stalled. |
| `core_reset_o` | 1 | Output | `u_adp.GPO8_o[0]` (`u_debugger.core_reset_o`) | Reset distribution network | Software-controllable core reset. | Controlled via `C 0201` (assert) and `C 0101` (deassert). Allows host to reboot processor firmware without requiring physical button presses. |

---

### Group 4: Debugger AHB-Lite Master 1 Interface (Debugger ↔ `ahb_mux.sv`)

The debugger acts as a fully compliant AMBA 3 AHB-Lite Master (Master 1):

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `DEBUG_HADDR[31:0]` | 32 | Output | `u_debugger.DEBUG_HADDR` | `ahb_mux.M1_HADDR` | Target memory address pointer. | Drives the 32-bit byte address set by host command `A <hex_addr>`. Auto-increments by 4 after each read (`R`) or write (`W`). |
| `DEBUG_HWDATA[31:0]` | 32 | Output | `u_debugger.DEBUG_HWDATA` | `ahb_mux.M1_HWDATA` | Write data bus from host. | Transmits the 32-bit data payload specified by command `W <hex_data>` into addressed register or SRAM. |
| `DEBUG_HRDATA[31:0]` | 32 | Input | `ahb_mux.M1_HRDATA` | `u_debugger.DEBUG_HRDATA` | Read data bus returning to host. | Captured from target slave when `DEBUG_HREADY` is HIGH during a read transfer (`R`). ADP converts hex word to ASCII for display. |
| `DEBUG_HWRITE` | 1 | Output | `u_debugger.DEBUG_HWRITE` | `ahb_mux.M1_HWRITE` | Transfer direction strobe. | `1` = Write transfer (`W` command). `0` = Read transfer (`R`, `P`, `F`, `U` commands). |
| `DEBUG_HTRANS[1:0]` | 2 | Output | `u_debugger.DEBUG_HTRANS` | `ahb_mux.M1_HTRANS` | AHB transfer classification. | `2'b00` (`IDLE`): Debugger not using bus.<br/>`2'b10` (`NONSEQ`): Debugger initiating single word access. |
| `DEBUG_HSIZE[2:0]` | 3 | Output | `u_debugger.DEBUG_HSIZE` | `ahb_mux.M1_HSIZE` | Transfer burst width. | Set to `3'b010` (32-bit Word access), or `3'b000` (Byte) / `3'b001` (Halfword). |
| `DEBUG_HBURST[2:0]` | 3 | Output | `u_debugger.DEBUG_HBURST` | `ahb_mux.M1_HBURST` | Burst sequence definition. | Set to `3'b000` (`SINGLE` transfer mode). |
| `DEBUG_HPROT[3:0]` | 4 | Output | `u_debugger.DEBUG_HPROT` | `ahb_mux.M1_HPROT` | Bus protection attributes. | Set to `4'b0011` (Privileged, non-bufferable, data access) to bypass MMU / PMP restrictions. |
| `DEBUG_HMASTLOCK` | 1 | Output | `u_debugger.DEBUG_HMASTLOCK` | `ahb_mux.M1_HMASTLOCK` | Atomic bus locking. | Tied to `1'b0` (unlocked standard transfer). |
| `DEBUG_HREADY` | 1 | Input | `ahb_mux.M1_HREADY` | `u_debugger.DEBUG_HREADY` | Transfer completion handshake. | Gated by `ahb_mux`. When HIGH, signals that target slave has accepted write data or that read data is valid on `HRDATA`. Non-granted active masters are held with `HREADY=0`. |
| `DEBUG_HRESP` | 1 | Input | `ahb_mux.M1_HRESP` | `u_debugger.DEBUG_HRESP` | Slave bus error indicator. | `1'b0` (`OKAY`): Normal completion.<br/>`1'b1` (`ERROR`): Slave error or unmapped address. Triggers `'!'` character response over UART. |

---

### Group 5: CPU Core AHB-Lite Master 0 Interface (Core ↔ `ahb_mux.sv`)

The CPU Core functions as Master 0 on the shared bus:

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `core_haddr[31:0]` | 32 | Output | `core.HADDR` | `ahb_mux.M0_HADDR` | CPU Instruction/Data address bus. | Driven by CPU IFU (instruction fetch) or LSU (load/store execution). |
| `core_hwdata[31:0]` | 32 | Output | `core.HWDATA` | `ahb_mux.M0_HWDATA` | CPU store data bus. | Store payload driven during execution of `sw`, `sh`, `sb` instructions. |
| `core_hrdata[31:0]` | 32 | Input | `ahb_mux.M0_HRDATA` | `core.HRDATA` | CPU read data bus. | Load data returned to CPU general-purpose register file or IFU cache. |
| `core_hwrite` | 1 | Output | `core.HWRITE` | `ahb_mux.M0_HWRITE` | CPU transfer direction. | `1` = Store instruction. `0` = Instruction fetch or Load instruction. |
| `core_htrans[1:0]` | 2 | Output | `core.HTRANS` | `ahb_mux.M0_HTRANS` | CPU bus transfer request. | `2'b00` (`IDLE`): Core not accessing external bus (allows cycle-stealing).<br/>`2'b10` (`NONSEQ`) / `2'b11` (`SEQ`): Active memory transfer. |
| `core_hsize[2:0]` | 3 | Output | `core.HSIZE` | `ahb_mux.M0_HSIZE` | CPU transfer size. | Encodes transfer size (`3'b000` byte, `3'b001` halfword, `3'b010` word). |
| `core_hready` | 1 | Input | `ahb_mux.M0_HREADY` | `core.HREADY` | CPU bus wait-state control. | When LOW, stalls CPU LSU/IFU pipeline stages until downstream memory finishes. |
| `core_hresp` | 1 | Input | `ahb_mux.M0_HRESP` | `core.HRESP` | CPU bus error response. | Triggers precise bus error exception trap in RISC-V CSR unit on invalid memory access. |

---

### Group 6: AHB Bus Arbiter / Mux Downstream Bus (`ahb_mux.sv` ↔ `uncore.sv`)

`ahb_mux.sv` multiplexes Master 0 (CPU) and Master 1 (Debugger) onto the downstream system bus (`S_*`):

| Signal Name | Width | Direction | Source Pin | Destination Pin | Engineering Reason | Function & Protocol Behavior |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| `S_HADDR[31:0]` | 32 | Output | `ahb_mux.S_HADDR` | `uncore.HADDR` | Multiplexed system address bus. | Driven by `M1_HADDR` if `grant_addr == 1'b1`, otherwise driven by `M0_HADDR`. |
| `S_HWDATA[31:0]` | 32 | Output | `ahb_mux.S_HWDATA` | `uncore.HWDATA` | Multiplexed system write data bus. | Driven by `M1_HWDATA` if `grant_data == 1'b1`, otherwise driven by `M0_HWDATA`. |
| `S_HWRITE` | 1 | Output | `ahb_mux.S_HWRITE` | `uncore.HWRITE` | Multiplexed write enable. | Driven by current address-phase master. |
| `S_HTRANS[1:0]` | 2 | Output | `ahb_mux.S_HTRANS` | `uncore.HTRANS` | Multiplexed transfer type. | Driven by current address-phase master. |
| `S_HSIZE[2:0]` | 3 | Output | `ahb_mux.S_HSIZE` | `uncore.HSIZE` | Multiplexed transfer size. | Driven by current address-phase master. |
| `S_HRDATA[31:0]` | 32 | Input | `uncore.HRDATA` | `ahb_mux.S_HRDATA` | System read data broadcast. | Routed back directly to both `M0_HRDATA` and `M1_HRDATA`. |
| `S_HREADY` | 1 | Input | `uncore.HREADY` | `ahb_mux.S_HREADY` | Downstream ready acknowledgement. | Clocked into `grant_addr` and `grant_data` to advance AHB pipelined phases. |
| `S_HRESP` | 1 | Input | `uncore.HRESP` | `ahb_mux.S_HRESP` | Downstream bus fault status. | Steered strictly to whichever master is currently in the data phase (`grant_data`). |

---

### Group 7: Downstream Interconnect & Target Slave Memory Map

`uncore.sv` decodes `HADDR` via `adrdecs` and activates individual chip selects (`HSEL*`):

```
+---------------------------------------------------------------------------------------+
|                                     MEMORY MAP                                        |
+--------------------------+-----------------------+------------------+-----------------+
| Region Address Range     | Target Slave Module   | Chip Select Wire | Access Type     |
+--------------------------+-----------------------+------------------+-----------------+
| 0x3000_0000 - 0x30FF_FFFF| 1TOPS Accelerator     | HSELEXT          | R/W (16 MB)     |
| 0x8000_0000 - 0x8000_1FFF| Instruction RAM       | HSELRam          | R/W (8 KB)      |
| 0x8000_2000 - 0x8000_3FFF| Data RAM              | HSELDRAM         | R/W (8 KB)      |
| 0x0001_0000 - 0x0001_FFFF| Boot ROM              | HSELBootRom      | Read-Only(64 KB)|
| 0x0200_0000 - 0x1001_FFFF| APB Peripheral Bridge | HSELBRIDGE       | R/W (Peripherals|
+--------------------------+-----------------------+------------------+-----------------+
```

#### Slave 1: Dedicated Hardware Accelerator (`multiplier_ahb.sv` / 1TOPS CTM)
- **Base Address**: `0x3000_0000` (16 Megabyte dedicated window).
- **Wiring Connections**:
  - `HSELEXT` (Input): Active-high slave chip select decoded by `adrdecs.ddr4dec`.
  - `HADDR[31:0]`, `HWDATA[31:0]`, `HWRITE`, `HTRANS`, `HSIZE`, `HREADY` (Inputs): Standard AHB bus controls.
  - `HRDATAEXT[31:0]` (Output): Returns calculated product (42 / `0x0000002A`), status bits, or weight memory.
  - `HREADYEXT` (`HREADYOUT`) (Output): Driven LOW while internal math/tensor engine is calculating; HIGH when done.
  - `HRESPEXT` (Output): Returns `1'b0` (`OKAY`).
- **Accelerator Internal Register Map**:
  - `0x3000_0000`: Operand A / Control Register (`ACC_REG_CTRL`) — Bit 0: Start, Bit 1: Soft Reset, Bit 2: IRQ Enable.
  - `0x3000_0004`: Operand B / Status Register (`ACC_REG_STATUS`) — Bit 0: Busy, Bit 1: Done, Bit 2: Error.
  - `0x3000_0008`: Product Output / Config Register (`ACC_REG_CONFIG`) — Fixed test product (`42`) or model precision.
  - `0x3000_000C`: Console Output / Cycle Counter (`ACC_REG_CYCLES`) — Hardware cycle timer.
  - `0x3000_1000 - 0x300F_FFFF` (~1 MB): Input Activations / Feature Buffers.
  - `0x3010_0000 - 0x307F_FFFF` (~7 MB): Model Weights / Clause Memory.
  - `0x3080_0000 - 0x30FF_FFFF` (~8 MB): Output Class Predictions Buffer.

#### Slave 2: Instruction SRAM (`ram_ahb ram_i`)
- **Base Address**: `0x8000_0000` (8 KB size).
- **Select Wire**: `HSELRam`.
- **Read Wire**: `HREADRam[31:0]`, Ready: `HREADYRamI`.
- **Purpose**: Stores executable machine instructions (`test_instr.mem`). The debugger can upload compiled binary firmware directly into this RAM using the `'U'` upload command.

#### Slave 3: Data SRAM (`ram_ahb ram_d`)
- **Base Address**: `0x8000_2000` (8 KB size).
- **Select Wire**: `HSELDRAM`.
- **Read Wire**: `HREADSDC[31:0]`, Ready: `HREADYRamD`.
- **Purpose**: Stores runtime global variables, stack, and heap (`test_data.mem`). While the CPU is frozen, the debugger can inspect or modify any variable live.

#### Slave 4: Boot ROM (`rom_ahb bootrom`)
- **Base Address**: `0x0001_0000` (64 KB size).
- **Select Wire**: `HSELBootRom`.
- **Read Wire**: `HREADBootRom[31:0]`, Ready: `HREADYBootRom`.
- **Purpose**: Contains the hardwired reset vector and bootloader code. Read-only; write attempts return bus errors.

#### Slave 5: AHB-to-APB Bridge & Peripherals (`ahbapbbridge.sv`)
- **Select Wire**: `HSELBRIDGE` (covers `0x0200_0000 - 0x1001_FFFF`).
- **Read Wire**: `HREADBRIDGE[31:0]`, Ready: `HREADYBRIDGE`.
- **Translates AHB transfers to APB transfers** (`PADDR`, `PWDATA`, `PRDATA`, `PSEL[5:0]`, `PENABLE`, `PWRITE`):
  - `PSEL[0]`: **GPIO Controller** (`0x1001_2000`) — 32-bit pin inputs/outputs.
  - `PSEL[1]`: **CLINT** (`0x0200_0000`) — Core Local Interruptor: `MTIME` (64-bit), `MTIMECMP`, `MSIP`.
  - `PSEL[2]`: **PLIC** (`0x0C00_0000`) — Platform-Level Interrupt Controller: Priorities & Enables.
  - `PSEL[3]`: **SoC 16550 UART** (`0x1001_3000`) — The integrated 16550 UART (`uartPC16550D.sv` / `uart_apb.sv`) that services both application serial printfs and hardware debug streaming.
  - `PSEL[4]`: **SPI Controller** (`0x1001_4000`) — SPI Master for external Flash / Sensors.
  - `PSEL[5]`: **SDC / APB Slot** (`0x1001_5000`) — SD Card controller or secondary APB debug hook.

---

## 4. Hardware Bus Arbitration Priority Truth Table

`ahb_mux.sv` arbitrates bus ownership between Master 0 (CPU Core) and Master 1 (Debugger) using a 2-phase pipelined state register (`grant_addr` and `grant_data`):

| `core_halt` | CPU Request (`m0_req`) | Debugger Request (`m1_req`) | Next Address Master (`grant_addr`) | Pipelined Data Master (`grant_data`) | Operational Behavior & Bus Control |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **`1` (Halted)** | Don't Care | `1` (Active) | **`1` (Debugger M1)** | `grant_addr` (1 cycle delay) | **Core is paused.** Debugger has 100% bus ownership. Zero bus collisions. Full static control. |
| **`1` (Halted)** | Don't Care | `0` (Idle) | Hold Last | `grant_addr` | **Core is paused.** Debugger idle; bus holds quiet state. |
| **`0` (Running)** | `1` (Active) | `1` (Active) | **`0` (CPU Core M0)** | `grant_addr` (1 cycle delay) | **CPU has top priority.** User software & real-time interrupts are NEVER delayed. Debugger waits 1 cycle. |
| **`0` (Running)** | `1` (Active) | `0` (Idle) | **`0` (CPU Core M0)** | `grant_addr` (1 cycle delay) | Normal software execution. CPU transfers at full hardware wire speed. |
| **`0` (Running)** | `0` (Idle) | `1` (Active) | **`1` (Debugger M1)** | `grant_addr` (1 cycle delay) | **CYCLE STEALING:** CPU bus is IDLE (cache hit / internal math). Debugger steals bus with 0 software penalty! |
| **`0` (Running)** | `0` (Idle) | `0` (Idle) | Hold Last | Hold Last | Both masters idle. Bus parked in power-efficient state. |

---

## 5. End-to-End Operational Walkthroughs

### Walkthrough A: Halting the Core, Peeking the Accelerator, and Resuming

```
 Host PC (Terminal)           Uncore 16550 UART (Sin/Sout)       Debugger ADP (riscv_debugger_top)    Hazard Unit (hazard.sv)   AHB Bus & Accelerator
         |                                  |                                   |                             |                         |
 (1) Send 'C 0202\n' ---------------------> |                                   |                             |                         |
         |                         UART RX done (0x43 'C')                      |                             |                         |
         |                                  | ----- dbg_uart_rx_data/valid ---> |                             |                         |
         |                                  |                                   | Decodes 'C', sets GPO8[1]   |                         |
         |                                  |                                   | ----- core_halt_o = 1 ----->|                         |
         |                                  |                                   |                             | StallF..W = 1           |
         |                                  |                                   |                             | [All 5 Stages Frozen]   |
         |                                  |                                   | ----- core_halt_o = 1 ------------------------------->| [M1 Priority = 100%]
         |                                  |                                   |                             |                         |
 (2) Send 'A 30000008\n' -----------------> |                                   |                             |                         |
         |                                  | ----- dbg_uart_rx_data/valid ---> |                             |                         |
         |                                  |                                   | HADDR = 0x30000008          |                         |
         |                                  |                                   |                             |                         |
 (3) Send 'R\n' --------------------------> |                                   |                             |                         |
         |                                  | ----- dbg_uart_rx_data/valid ---> |                             |                         |
         |                                  |                                   | Initiates AHB Read Cycle    |                         |
         |                                  |                                   | ====================================================> | S_HADDR = 0x30000008
         |                                  |                                   |                                                       | HSELEXT = 1
         |                                  |                                   |                                                       | Reads Product = 42
         |                                  |                                   | <==================================================== | HRDATAEXT = 32'h2A
         |                                  |                                   | Captures 0x0000002A         |                         |
         |                                  | <---- dbg_uart_tx_data/valid ---- | Formats 'R 0x0000002A\n]'   |                         |
         |                                  | (Loads UART TX Shift Register)    |                             |                         |
 (4) Recv 'R 0x0000002A\n]' <-------------- | Serializes byte over UARTSout      |                             |                         |
         |                                  |                                   |                             |                         |
 (5) Send 'C 0102\n' ---------------------> |                                   |                             |                         |
         |                                  | ----- dbg_uart_rx_data/valid ---> |                             |                         |
         |                                  |                                   | Decodes 'C', clears GPO8[1] |                         |
         |                                  |                                   | ----- core_halt_o = 0 ----->|                         |
         |                                  |                                   |                             | StallF..W = 0           |
         |                                  |                                   |                             | [Pipeline Resumes!]     |
```

1. **Host Halts the Core**:
   User types `C 0202`. The character stream enters physical pin `UARTSin`. `uartPC16550D` completes byte reception and forwards characters via `dbg_uart_rx_data` / `dbg_uart_rx_valid` to `riscv_debugger_top`. `socdebug_adp_control` asserts `GPO8[1]`, driving `core_halt_o = 1`.
   `hazard.sv` catches this on `ExternalStall` and freezes all 5 stages in place.
2. **Host Sets Target Address**:
   User types `A 30000008`. ADP stores `0x3000_0008` in its address register and streams response text `A 0x30000008` back to `uartPC16550D` via `dbg_uart_tx_data`, transmitting out `UARTSout`.
3. **Host Reads Word**:
   User types `R`. Debugger drives `DEBUG_HTRANS = 2'b10`, `DEBUG_HWRITE = 0`, and `DEBUG_HADDR = 0x30000008`.
   `ahb_mux` forwards the transfer to `uncore.sv`. `adrdecs` asserts `HSELEXT`.
   `multiplier_ahb.sv` reads its Product register and outputs `32'h0000002A` (42).
   ADP converts `0x0000002A` into ASCII text and sends `R 0x0000002A\n]` over `dbg_uart_tx_*` to `uartPC16550D` $\rightarrow$ `UARTSout`.
4. **Host Resumes the Core**:
   User types `C 0102`. ADP clears `GPO8[1]`, lowering `core_halt_o = 0`.
   The CPU pipeline unfreezes and resumes executing instructions from the exact cycle without missing a beat.

---

## 6. Integration Checklist for `wallypipelinedsoc.sv`

When instantiating the debugger subsystem in the top-level SoC:
1. **Instantiate `riscv_debugger_top`**:
   Connect `clk` to `HCLK`, `rst_n` to `HRESETn`. Connect `uart_rx_data`, `uart_rx_valid`, `uart_rx_ready` to `uncore`'s `dbg_uart_rx_*` outputs/inputs. Connect `uart_tx_data`, `uart_tx_valid`, `uart_tx_ready` to `uncore`'s `dbg_uart_tx_*` inputs/outputs.
2. **Connect Halt Wire**:
   Route `core_halt_o` directly to `.ExternalStall` of `wallypipelinedcore` (or ORed with existing `ExternalStall`).
3. **Insert `ahb_mux`**:
   Connect Master 0 to CPU core outputs (`core_h*`), Master 1 to debugger outputs (`dbg_h*`), and Downstream Slave port (`S_*`) to `uncore`.
4. **Connect SoC Physical UART Pins**:
   Wire `uncore`'s `UARTSin` and `UARTSout` to top-level external pins. No extra serial pins are required!
5. **Verify Accelerator Address**:
   Ensure `EXT_MEM_BASE` is configured to `0x30000000` with range `0x00FFFFFF` (16 MB) in [`accelerator_debug_def.vh`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/accelerator_debug_def.vh).
