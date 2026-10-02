# CORE-V Wally RISC-V SoC: Complete Debugger Wiring Architecture & Signal Specification

This specification provides the exhaustive, pin-by-pin wiring connection map for the **SoCDebug hardware debugger subsystem** within the **CORE-V Wally RISC-V SoC** (`1tops_soc`). It covers all interconnects:
- **Dedicated Debugger UART Transceiver** (`socdebug_uart.v`) with independent external serial pins (`uart_rx`, `uart_tx`).
- **Separate Uncore 16550 UART** (`uartPC16550D.sv` / `uart_apb.sv`) connected independently to `UARTSin` and `UARTSout` for application I/O.
- **ASCII Debug Protocol (ADP) Controller** (`socdebug_adp_control.v` / `socdebug_ahb.v`).
- **RISC-V CPU Pipeline Hazard Unit & Stall Hooks** (`hazard.sv` / `wallypipelinedcore.sv`).
- **2-Master AHB-Lite Bus Arbiter / Mux** (`ahb_mux.sv`).
- **Downstream Memory & Accelerator Slaves** (1TOPS Accelerator, IRAM, DRAM, Boot ROM, APB Bridge).

---

## 1. High-Resolution Architecture Schematic

![CORE-V Wally RISC-V SoC Debugger Full Wiring Architecture](debugger_wiring_diagram.png)

> [!NOTE]
> - **Workspace Copy (PNG)**: [`debugger_wiring_diagram.png`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/debugger_wiring_diagram.png)
> - **Vector Copy (Scalable SVG)**: [`debugger_wiring_diagram.svg`](file:///home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger/debugger_wiring_diagram.svg)

---

## 2. Top-Level Subsystem Block Hierarchy

```mermaid
graph TD
    classDef host fill:#1e293b,stroke:#0f172a,color:#fff
    classDef dbguart fill:#1d4ed8,stroke:#1e3a8a,color:#fff
    classDef uncoreuart fill:#581c87,stroke:#6b21a8,color:#fff
    classDef adp fill:#0284c7,stroke:#0369a1,color:#fff
    classDef core fill:#b45309,stroke:#92400e,color:#fff
    classDef hazard fill:#b91c1c,stroke:#991b1b,color:#fff
    classDef mux fill:#0f766e,stroke:#115e59,color:#fff
    classDef uncore fill:#6b21a8,stroke:#581c87,color:#fff
    classDef slave fill:#065f46,stroke:#064e3b,color:#fff

    subgraph Host["Host PC / Workstation"]
        CLI["Debugger CLI (dbg_cli.py @ 115200 Baud)"]:::host
        TERM["User Terminal (Serial Console)"]:::host
    end

    subgraph DbgSub["Debugger Subsystem: riscv_debugger_top.sv"]
        DBG_UART["Dedicated Debugger UART<br/>socdebug_uart.v<br/>(115200 Baud, 8-N-1)"]:::dbguart
        ADP["ADP Controller & AHB Master<br/>socdebug_adp_control.v / socdebug_ahb.v"]:::adp
    end

    subgraph UncoreSub["Uncore Subsystem: uncore.sv"]
        UNC_UART["Uncore 16550 UART<br/>uartPC16550D.sv / uart_apb.sv<br/>Base: 0x1001_3000"]:::uncoreuart
        DEC["Address Decoder (adrdecs.sv)<br/>Delay Register (hseldelayreg)"]:::uncore
        RMUX["HRDATA / HREADY / HRESP<br/>Read Multiplexer & Gating"]:::uncore
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

    CLI -->|uart_rx (Dedicated Pin)| DBG_UART
    DBG_UART -->|uart_tx (Dedicated Pin)| CLI

    DBG_UART -->|adp_rxd_data/valid/ready| ADP
    ADP -->|adp_txd_data/valid/ready| DBG_UART

    TERM -->|UARTSin (Physical Pin)| UNC_UART
    UNC_UART -->|UARTSout (Physical Pin)| TERM

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

## 3. Dedicated vs Uncore UART Comparison

| Feature | Debugger UART (`socdebug_uart.v`) | Uncore UART (`uartPC16550D.sv`) |
| :--- | :--- | :--- |
| **Location** | Inside `riscv_debugger_top.sv` | Inside `uncore.sv` (APB peripheral) |
| **Physical Pins** | `uart_rx`, `uart_tx` | `UARTSin`, `UARTSout` |
| **Bus Interface** | AXI-Stream (`adp_rxd_*`, `adp_txd_*`) | APB Slave (`PADDR`, `PWDATA`, `PRDATA`, `PSEL`) |
| **Protocol** | ASCII Debug Protocol (ADP) commands | 16550D standard UART register set |
| **Clock Domain** | SoC Clock (`clk`, 50 MHz) | Peripheral Bus Clock (`PCLK`) |
| **Independence** | Fully independent; can debug even if uncore is halted or reset | Unaffected by debugger operation; available for application logs |

---

## 4. Signal Specification Table: `riscv_debugger_top.sv`

| Signal Name | Width | Dir | Driven By / Connects To | Functional Description |
| :--- | :---: | :---: | :--- | :--- |
| `clk` | 1 | In | Top-level SoC Clock (`clk`) | Master clock (50 MHz default). |
| `rst_n` | 1 | In | System Active-Low Reset (`reset`) | Asynchronous active-low reset. |
| `uart_rx` | 1 | In | External Dedicated Debug Pin | Serial ingress from host debugger CLI. |
| `uart_tx` | 1 | Out | External Dedicated Debug Pin | Serial egress to host debugger CLI. |
| `core_halt_o` | 1 | Out | `ExternalStall` & `ahb_mux.core_halt` | **Pipeline Freeze Hook**: Asserts `1` to freeze all 5 pipeline stages. |
| `core_reset_o` | 1 | Out | Reset Controller | Software reset request. |
| `core_halted_i` | 1 | In | `hazard.sv` status feedback | Core halt acknowledgment. |
| `DEBUG_HADDR` | 32 | Out | `ahb_mux.M1_HADDR` | Master 1 AHB byte address. |
| `DEBUG_HWDATA` | 32 | Out | `ahb_mux.M1_HWDATA` | Master 1 AHB write data. |
| `DEBUG_HWRITE` | 1 | Out | `ahb_mux.M1_HWRITE` | Master 1 AHB write direction (`1`=Write, `0`=Read). |
| `DEBUG_HTRANS` | 2 | Out | `ahb_mux.M1_HTRANS` | Master 1 transfer type (`2'b10`=NONSEQ, `2'b00`=IDLE). |
| `DEBUG_HSIZE` | 3 | Out | `ahb_mux.M1_HSIZE` | Transfer size (`3'b010`=Word, `3'b001`=Half, `3'b000`=Byte). |
| `DEBUG_HBURST` | 3 | Out | `ahb_mux.M1_HBURST` | Burst encoding (`3'b000`=SINGLE). |
| `DEBUG_HPROT` | 4 | Out | `ahb_mux.M1_HPROT` | Protection control (`4'b0011`=Privileged Data). |
| `DEBUG_HMASTLOCK` | 1 | Out | `ahb_mux.M1_HMASTLOCK` | Master lock signal (`1'b0`). |
| `DEBUG_HRDATA` | 32 | In | `ahb_mux.M1_HRDATA` | Master 1 AHB read data return. |
| `DEBUG_HREADY` | 1 | In | `ahb_mux.M1_HREADY` | Master 1 transfer ready acknowledgment. |
| `DEBUG_HRESP` | 1 | In | `ahb_mux.M1_HRESP` | Master 1 error response (`1`=Error). |
| `GPO8` | 8 | Out | Open / Test header | General-purpose outputs (`bit 1`=Halt, `bit 0`=Reset). |
| `GPI8` | 8 | In | Tied to `8'h00` | General-purpose status inputs. |

---

## 5. Bus Arbiter Specification: `ahb_mux.sv`

`ahb_mux.sv` implements a 2-to-1 AHB-Lite bus arbiter connecting Master 0 (CPU Core) and Master 1 (Debugger) to downstream slaves:

```
          +-----------------------+
M0 (CPU)  |                       |
--------->|  ahb_mux.sv           |
          |  - core_halt priority |=======> S_* (Downstream AHB Slaves)
M1 (DBG)  |  - pipelined grant    |
--------->|                       |
          +-----------------------+
```

- **Priority Arbitration**: When `core_halt = 1`, Master 1 (Debugger) is granted unconditional exclusive bus ownership.
- **Pipelined Tracking**: Addresses driven in phase $N$ are paired with data phases in $N+1$ via registered `grant_data`.
- **Slave Multiplexing**: Return data (`HRDATA`), `HREADY`, and `HRESP` are routed back exclusively to the granted master.

---

## 6. Simulation & Verification

To compile and verify the debugger subsystem with separate UART architecture:

```bash
cd /home/23EC01043/Desktop/cores/Ganesh_CVW/cvw/1tops_soc/src/debugger
vlog -sv socdebug_adp_control.v socdebug_ahb.v socdebug_uart.v riscv_debugger_top.sv ahb_mux.sv ../accelerator/multiplier_ahb.sv tb/tb_debugger.sv
vsim -c -do "run -all; quit" tb_debugger
```

**Verified Testbench Outputs:**
- **Test 1**: Halts RISC-V core via UART `C 0202\n` $\rightarrow$ `core_halt_o = 1`.
- **Test 2**: Reads 32-bit accelerator product from `0x30000008` over AHB $\rightarrow$ Returns `42` (`0x0000002A`).
- **Test 3**: Resumes RISC-V core via UART `C 0102\n` $\rightarrow$ `core_halt_o = 0`.
- **Result**: `Errors: 0, Warnings: 0`.
