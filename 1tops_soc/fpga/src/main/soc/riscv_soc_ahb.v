// =============================================================================
// Module: riscv_soc_ahb
// Purpose: Pipelined RV32I System-on-Chip integrating:
//            1. Pipelined Processor Core (riscv_cpu)
//            2. Uncore Subsystem (Instruction RAM, Data RAM, APB Peripherals)
//            3. Dedicated External AHB Slave Socket (multiplier_ahb Accelerator)
// Reference: cvw/1tops_soc/src/wally/wallypipelinedsoc.sv (David_Harris@hmc.edu)
// =============================================================================

module riscv_soc_ahb #(
    parameter RESET_PC        = 32'h8000_0000,
    parameter MEM_SIZE_BYTES  = 16384,
    parameter IRAM_BASE        = 32'h8000_0000,
    parameter IRAM_SIZE_BYTES  = MEM_SIZE_BYTES / 2,
    parameter DRAM_BASE        = IRAM_BASE + (MEM_SIZE_BYTES / 2),
    parameter DRAM_SIZE_BYTES  = MEM_SIZE_BYTES / 2,
    parameter CLK_FREQ         = 100_000_000,
    parameter BAUD_RATE        = 115200,
    parameter PROMPT_CHAR      = "]",
    parameter FT_WIDTH         = 1,
    parameter FT_CLKDIV        = 8'd4
)(
    input             clk,
    input             reset,

    // Hardware Interrupt Lines
    input             MExtInt,
    output            TrapM,
    output            mretM,

    // Execution Trace Outputs (Testbench and verification hooks)
    output     [31:0] PCW,
    output     [31:0] ResultW,

    // Peripheral I/O Pins (Wally-compatible)
    input      [31:0] GPIOIN,
    output     [31:0] GPIOOUT,
    output     [31:0] GPIOEN,
    input             UARTSin,
    output            UARTSout,
    input             SPIIn,
    output            SPIOut,
    output     [ 3:0] SPICS,
    output            SPICLK,

    // Dual-Protocol Debugger Hardware Pins (Direct FPGA Connections, Wally-compatible)
    input             dbg_sel,         // 0 = Dedicated UART, 1 = Dedicated FT1248
    input             uart_rx,         // Dedicated Debugger UART RX (idle HIGH)
    output            uart_tx,         // Dedicated Debugger UART TX
    output            ft1248_clk,      // SCLK output to FT232H
    output            ft1248_ss_n,     // SS# output to FT232H
    input             ft1248_miso,     // MISO / RXF# input (idle HIGH)
    inout      [0:0]  ft1248_miosio,   // Bidirectional MIOSIO data bus
    output            core_halted_led  // LED output indicating core is halted
);

    wire HCLK    = clk;
    wire HRESETn = ~reset;

    // -------------------------------------------------------------------------
    // AMBA 3 AHB-Lite Master Signals: Master 0 (CPU Core)
    // -------------------------------------------------------------------------
    wire [31:0] core_HADDR;
    wire [31:0] core_HWDATA;
    wire [ 3:0] core_HWSTRB;
    wire        core_HWRITE;
    wire [ 2:0] core_HSIZE;
    wire [ 2:0] core_HBURST;
    wire [ 3:0] core_HPROT;
    wire [ 1:0] core_HTRANS;
    wire        core_HMASTLOCK;
    wire [31:0] core_HRDATA;
    wire        core_HREADY;
    wire        core_HRESP;

    // -------------------------------------------------------------------------
    // AMBA 3 AHB-Lite Master Signals: Master 1 (Debugger Subsystem)
    // -------------------------------------------------------------------------
    wire [31:0] dbg_HADDR;
    wire [31:0] dbg_HWDATA;
    wire        dbg_HWRITE;
    wire [ 2:0] dbg_HSIZE;
    wire [ 2:0] dbg_HBURST;
    wire [ 3:0] dbg_HPROT;
    wire [ 1:0] dbg_HTRANS;
    wire        dbg_HMASTLOCK;
    wire [31:0] dbg_HRDATA;
    wire        dbg_HREADY;
    wire        dbg_HRESP;

    // -------------------------------------------------------------------------
    // Shared Downstream Interconnect Signals (Multiplexed by ahb_mux)
    // -------------------------------------------------------------------------
    wire [31:0] HADDR;
    wire [31:0] HWDATA;
    wire [ 3:0] HWSTRB;
    wire        HWRITE;
    wire [ 2:0] HSIZE;
    wire [ 2:0] HBURST;
    wire [ 3:0] HPROT;
    wire [ 1:0] HTRANS;
    wire        HMASTLOCK;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;
    wire        HREADYOUT_uncore;

    // AHB Bus HREADY Loopback
    assign HREADY = HREADYOUT_uncore;

    // External AHB Slave / Hardware Accelerator Signals (Wally 1tops_soc Socket)
    wire        HSELEXT;
    wire [31:0] HRDATAEXT;
    wire        HREADYEXT;
    wire        HRESPEXT;

    // Interrupt & Timer Signals from Uncore to Core
    wire        MTimerInt;
    wire        MSwInt;
    wire        MExtInt_uncore;
    wire [63:0] MTIME_CLINT;

    // Combine PLIC external interrupt with external chip pin
    wire        core_MExtInt = MExtInt | MExtInt_uncore;

    // Safe default handling for I/O pins when unassigned in simple testbenches
`ifdef ALTERA_RESERVED_QIS
    wire [31:0] gpio_in_safe      = GPIOIN;
    wire        uart_sin_safe     = UARTSin;
    wire        spi_in_safe       = SPIIn;
    wire        dbg_sel_safe      = dbg_sel;
    wire        uart_rx_safe      = uart_rx;
    wire        ft1248_miso_safe  = ft1248_miso;
`elsif SYNTHESIS
    wire [31:0] gpio_in_safe      = GPIOIN;
    wire        uart_sin_safe     = UARTSin;
    wire        spi_in_safe       = SPIIn;
    wire        dbg_sel_safe      = dbg_sel;
    wire        uart_rx_safe      = uart_rx;
    wire        ft1248_miso_safe  = ft1248_miso;
`elsif VERILATOR
    wire [31:0] gpio_in_safe      = GPIOIN;
    wire        uart_sin_safe     = UARTSin;
    wire        spi_in_safe       = SPIIn;
    wire        dbg_sel_safe      = dbg_sel;
    wire        uart_rx_safe      = uart_rx;
    wire        ft1248_miso_safe  = ft1248_miso;
`else
    // synthesis translate_off
    wire [31:0] gpio_in_safe      = (GPIOIN  === 32'bzzzz_zzzz_zzzz_zzzz_zzzz_zzzz_zzzz_zzzz || GPIOIN === 32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx) ? 32'd0 : GPIOIN;
    wire        uart_sin_safe     = (UARTSin === 1'bz || UARTSin === 1'bx) ? 1'b1 : UARTSin;
    wire        spi_in_safe       = (SPIIn   === 1'bz || SPIIn   === 1'bx) ? 1'b0 : SPIIn;
    wire        dbg_sel_safe      = (dbg_sel === 1'bz || dbg_sel === 1'bx) ? 1'b0 : dbg_sel;
    wire        uart_rx_safe      = (uart_rx === 1'bz || uart_rx === 1'bx) ? 1'b1 : uart_rx;
    wire        ft1248_miso_safe  = (ft1248_miso === 1'bz || ft1248_miso === 1'bx) ? 1'b1 : ft1248_miso;
    // synthesis translate_on
`endif

    // -------------------------------------------------------------------------
    // Debugger Subsystem Controls & Status Hooks
    // -------------------------------------------------------------------------
    wire        dbg_core_halt;
    wire        dbg_core_reset;
    wire        dbg_core_step;
    wire        dbg_core_step_mode;
    wire        dbg_step_busy;
    wire        dbg_step_done;
    wire        core_stall_effective;
    wire        dbg_core_halt_status;
    wire        auto_halt_trap;
    wire        dbg_trap_latched;
    wire [ 3:0] dbg_fault_flags;

    // 1. Dual-Protocol Hardware Debugger Subsystem (UART + FT1248)
    riscv_debugger_top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .PROMPT_CHAR(PROMPT_CHAR),
        .FT_WIDTH(FT_WIDTH),
        .FT_CLKDIV(FT_CLKDIV)
    ) u_debugger (
        .clk(clk),
        .rst_n(HRESETn),
        .dbg_sel(dbg_sel_safe),
        .uart_rx(uart_rx_safe),
        .uart_tx(uart_tx),
        .ft1248_clk(ft1248_clk),
        .ft1248_ss_n(ft1248_ss_n),
        .ft1248_miso(ft1248_miso_safe),
        .ft1248_miosio(ft1248_miosio),
        .core_halt_o(dbg_core_halt),
        .core_reset_o(dbg_core_reset),
        .core_halted_i(dbg_core_halt_status),
        .core_step_o(dbg_core_step),
        .core_step_mode_o(dbg_core_step_mode),
        .core_step_busy_i(dbg_step_busy),
        .core_step_done_i(dbg_step_done),
        .DEBUG_HADDR(dbg_HADDR),
        .DEBUG_HBURST(dbg_HBURST),
        .DEBUG_HMASTLOCK(dbg_HMASTLOCK),
        .DEBUG_HPROT(dbg_HPROT),
        .DEBUG_HSIZE(dbg_HSIZE),
        .DEBUG_HTRANS(dbg_HTRANS),
        .DEBUG_HWDATA(dbg_HWDATA),
        .DEBUG_HWRITE(dbg_HWRITE),
        .DEBUG_HRDATA(dbg_HRDATA),
        .DEBUG_HREADY(dbg_HREADY),
        .DEBUG_HRESP(dbg_HRESP),
        .GPO8(),
        .GPI8({dbg_fault_flags, dbg_trap_latched, dbg_step_done, dbg_step_busy, dbg_core_halt_status})
    );

    // 1.1 Step Debugging FSM Controller Instance
    wire core_instr_retired;
    wire core_HRESETn = HRESETn & ~dbg_core_reset;

    core_step_controller #(
        .WATCHDOG_LIMIT(65536)
    ) u_step_controller (
        .clk(clk),
        .rst_n(HRESETn),
        .halt_req_i(dbg_core_halt),
        .step_req_i(dbg_core_step),
        .step_mode_i(dbg_core_step_mode),
        .auto_halt_req_i(auto_halt_trap),
        .instr_retired_i(core_instr_retired),
        .core_stall_ext_i(1'b0),
        .core_stall_o(core_stall_effective),
        .step_busy_o(dbg_step_busy),
        .step_done_o(dbg_step_done),
        .step_count_o()
    );

    assign dbg_core_halt_status = core_stall_effective & ~dbg_step_busy;
    assign core_halted_led      = dbg_core_halt_status;

    // -------------------------------------------------------------------------
    // 2. 2-to-1 AHB-Lite Bus Arbiter / Multiplexer
    // -------------------------------------------------------------------------
    ahb_mux #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) u_ahb_mux (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .core_halt(dbg_core_halt_status),

        // Master 0: CPU Core
        .M0_HADDR(core_HADDR),
        .M0_HWDATA(core_HWDATA),
        .M0_HWRITE(core_HWRITE),
        .M0_HTRANS(core_HTRANS),
        .M0_HSIZE(core_HSIZE),
        .M0_HBURST(core_HBURST),
        .M0_HPROT(core_HPROT),
        .M0_HMASTLOCK(core_HMASTLOCK),
        .M0_HRDATA(core_HRDATA),
        .M0_HREADY(core_HREADY),
        .M0_HRESP(core_HRESP),

        // Master 1: Debugger Subsystem
        .M1_HADDR(dbg_HADDR),
        .M1_HWDATA(dbg_HWDATA),
        .M1_HWRITE(dbg_HWRITE),
        .M1_HTRANS(dbg_HTRANS),
        .M1_HSIZE(dbg_HSIZE),
        .M1_HBURST(dbg_HBURST),
        .M1_HPROT(dbg_HPROT),
        .M1_HMASTLOCK(dbg_HMASTLOCK),
        .M1_HRDATA(dbg_HRDATA),
        .M1_HREADY(dbg_HREADY),
        .M1_HRESP(dbg_HRESP),

        // Shared Downstream Interconnect to Uncore & Peripherals
        .S_HADDR(HADDR),
        .S_HWDATA(HWDATA),
        .S_HWRITE(HWRITE),
        .S_HTRANS(HTRANS),
        .S_HSIZE(HSIZE),
        .S_HBURST(HBURST),
        .S_HPROT(HPROT),
        .S_HMASTLOCK(HMASTLOCK),
        .S_HRDATA(HRDATA),
        .S_HREADY(HREADY),
        .S_HRESP(HRESP)
    );

    // Byte strobe generation for debugger writes
    reg [3:0] dbg_HWSTRB;
    always @(*) begin
        case (HSIZE[1:0])
            2'b00:   dbg_HWSTRB = 4'b0001 << HADDR[1:0];
            2'b01:   dbg_HWSTRB = 4'b0011 << {HADDR[1], 1'b0};
            default: dbg_HWSTRB = 4'b1111;
        endcase
    end
    assign HWSTRB = (dbg_core_halt_status) ? dbg_HWSTRB : core_HWSTRB;

    // =========================================================================
    // Core Post-Mortem Debug Wires
    // =========================================================================
    wire [ 4:0] dbg_rf_raddr;
    wire [31:0] dbg_rf_rdata;
    wire [31:0] core_PCF;
    wire [31:0] core_PCD;
    wire [31:0] core_PCE;
    wire [31:0] core_PCM;
    wire [31:0] core_InstrM;
    wire [31:0] core_TrapCauseM;
    wire [31:0] core_TrapValM;
    wire [31:0] core_mstatus;
    wire [31:0] core_mcause;
    wire [31:0] core_mtval;
    wire [31:0] core_mepc;
    wire [31:0] core_mtvec;
    wire [31:0] core_mie;
    wire [31:0] core_mip;
    wire [31:0] core_mscratch;
    wire [63:0] core_cycle_cnt;
    wire [63:0] core_instret_cnt;
    wire [ 4:0] core_stall_flags;
    wire [ 2:0] core_flush_flags;

    // Core Debug AHB Slave Interconnect Wires
    wire        HSELCOREDBG;
    wire [31:0] HRDATACOREDBG;
    wire        HREADYCOREDBG;
    wire        HRESPCOREDBG;

    // =========================================================================
    // 3. Pipelined Processor Core (Wally Core Equivalent)
    // =========================================================================
    riscv_cpu #(RESET_PC) cpu (
        .HCLK(HCLK),
        .HRESETn(core_HRESETn),
        .HADDR(core_HADDR),
        .HWDATA(core_HWDATA),
        .HWSTRB(core_HWSTRB),
        .HWRITE(core_HWRITE),
        .HSIZE(core_HSIZE),
        .HBURST(core_HBURST),
        .HPROT(core_HPROT),
        .HTRANS(core_HTRANS),
        .HMASTLOCK(core_HMASTLOCK),
        .HRDATA(core_HRDATA),
        .HREADY(core_HREADY),
        .HRESP(core_HRESP),
        .PC(core_PCF),
        .PCW(PCW),
        .ALUResultW(),
        .WriteDataW(),
        .Result(ResultW),
        .MTimerInt(MTimerInt),
        .MSwInt(MSwInt),
        .MExtInt(core_MExtInt),
        .MTIME_CLINT(MTIME_CLINT),
        .ExternalStall(core_stall_effective),
        .InstrRetired(core_instr_retired),
        .TrapM(TrapM),
        .mretM(mretM),
        .dbg_rf_raddr(dbg_rf_raddr),
        .dbg_rf_rdata(dbg_rf_rdata),
        .dbg_PCD(core_PCD),
        .dbg_PCE(core_PCE),
        .dbg_PCM(core_PCM),
        .dbg_InstrM(core_InstrM),
        .dbg_TrapCauseM(core_TrapCauseM),
        .dbg_TrapValM(core_TrapValM),
        .dbg_mstatus(core_mstatus),
        .dbg_mcause(core_mcause),
        .dbg_mtval(core_mtval),
        .dbg_mepc(core_mepc),
        .dbg_mtvec(core_mtvec),
        .dbg_mie(core_mie),
        .dbg_mip(core_mip),
        .dbg_mscratch(core_mscratch),
        .dbg_cycle_cnt(core_cycle_cnt),
        .dbg_instret_cnt(core_instret_cnt),
        .dbg_stall_flags(core_stall_flags),
        .dbg_flush_flags(core_flush_flags)
    );

    // =========================================================================
    // 2. Uncore Subsystem (Memories & APB Peripherals: CLINT, PLIC, UART, GPIO)
    // =========================================================================
    uncore #(
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES),
        .IRAM_BASE(IRAM_BASE),
        .IRAM_SIZE_BYTES(IRAM_SIZE_BYTES),
        .DRAM_BASE(DRAM_BASE),
        .DRAM_SIZE_BYTES(DRAM_SIZE_BYTES),
        .XLEN(32)
    ) uncore (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HREADY(HREADY),
        .HRDATA(HRDATA),
        .HREADYOUT(HREADYOUT_uncore),
        .HRESP(HRESP),
        .HSELEXT(HSELEXT),
        .HRDATAEXT(HRDATAEXT),
        .HREADYEXT(HREADYEXT),
        .HRESPEXT(HRESPEXT),
        .HSELCOREDBG(HSELCOREDBG),
        .HRDATACOREDBG(HRDATACOREDBG),
        .HREADYCOREDBG(HREADYCOREDBG),
        .HRESPCOREDBG(HRESPCOREDBG),
        .MTimerInt(MTimerInt),
        .MSwInt(MSwInt),
        .MExtInt(MExtInt_uncore),
        .SExtInt(),
        .MTIME_CLINT(MTIME_CLINT),
        .TIMECLK(1'b0),
        .GPIOIN(gpio_in_safe),
        .GPIOOUT(GPIOOUT),
        .GPIOEN(GPIOEN),
        .UARTSin(uart_sin_safe),
        .UARTSout(UARTSout),
        .SPIIn(spi_in_safe),
        .SPIOut(SPIOut),
        .SPICS(SPICS),
        .SPICLK(SPICLK),
        .SDCIn(1'b0),
        .SDCCmd(),
        .SDCCS(),
        .SDCCLK()
    );

    // =========================================================================
    // 3. Core Post-Mortem Debugging AHB Slave (0x0B00_0000 - 0x0B00_0FFF)
    // =========================================================================
    core_debug_ahb #(
        .DATA_WIDTH(32)
    ) u_core_dbg (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSEL(HSELCOREDBG),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HREADY(HREADY),
        .HREADYOUT(HREADYCOREDBG),
        .HRESP(HRESPCOREDBG),
        .HRDATA(HRDATACOREDBG),
        .dbg_rf_raddr(dbg_rf_raddr),
        .dbg_rf_rdata(dbg_rf_rdata),
        .PCF(core_PCF),
        .PCD(core_PCD),
        .PCE(core_PCE),
        .PCM(core_PCM),
        .PCW(PCW),
        .InstrD(32'd0),
        .InstrM(core_InstrM),
        .StallFlags(core_stall_flags),
        .FlushFlags(core_flush_flags),
        .ExternalStall(core_stall_effective),
        .InstrRetired(core_instr_retired),
        .TrapM(TrapM),
        .mretM(mretM),
        .TrapCauseM(core_TrapCauseM),
        .TrapValM(core_TrapValM),
        .mstatus(core_mstatus),
        .mcause(core_mcause),
        .mtval(core_mtval),
        .mepc(core_mepc),
        .mtvec(core_mtvec),
        .mie(core_mie),
        .mip(core_mip),
        .mscratch(core_mscratch),
        .cycle_cnt(core_cycle_cnt),
        .instret_cnt(core_instret_cnt),
        .auto_halt_trap_o(auto_halt_trap),
        .trap_latched_o(dbg_trap_latched),
        .fault_flags_o(dbg_fault_flags)
    );

    // =========================================================================
    // 4. External AHB Slave / Accelerator Interface (Wally 1tops_soc Multiplier)
    // =========================================================================
    // Space: 0x3000_0000 - 0x30FF_FFFF (Wally EXT_MEM space).
    // Provides a dedicated hardware socket to connect custom AHB accelerator slaves
    // (e.g. Multiplier Accelerator or Convolutional Tsetlin Machine).
    multiplier_ahb #(
        .XLEN(32)
    ) accel (
        .clk(clk),
        .reset(reset),
        .HSEL(HSELEXT),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HREADY(HREADY),
        .HREADYOUT(HREADYEXT),
        .HRESP(HRESPEXT),
        .HRDATA(HRDATAEXT)
    );

endmodule
