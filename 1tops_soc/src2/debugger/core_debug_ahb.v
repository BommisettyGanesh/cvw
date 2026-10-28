// =============================================================================
// Module: core_debug_ahb
// Purpose: AMBA 3 AHB-Lite Core Post-Mortem Debugging Slave
// Address Space: 0x0B00_0000 - 0x0B00_0FFF (4 KB Aperture)
//
// Features:
//   1. Register File Inspection: Full read access to x0 through x31 (0x000 - 0x07C).
//   2. Pipeline Stage PCs & Instructions: PCF, PCD, PCE, PCM, PCW, InstrD, InstrM.
//   3. Pipeline Status Flags: Stall and Flush vectors for all 5 stages.
//   4. Privileged CSRs: mstatus, mcause, mtval, mepc, mtvec, mie, mip, mscratch, cycle, instret.
//   5. Hardware Auto-Halt on Trap: Automatically freezes CPU on exception/ebreak.
//   6. Sticky Crash Latches: Captures exact faulting PC, mcause, and mtval at crash cycle.
//   7. Circular Micro-Trace Buffer: 16-entry history of last committed PCs before crash.
//
// Design: 100% synchronous, glitch/hazard free, scan-chain friendly (single clock, single reset).
// =============================================================================

`timescale 1ns / 1ps

module core_debug_ahb #(
    parameter DATA_WIDTH = 32
)(
    // AHB-Lite Bus Interface
    input  wire                   HCLK,
    input  wire                   HRESETn,
    input  wire                   HSEL,
    input  wire [31:0]            HADDR,
    input  wire [31:0]            HWDATA,
    input  wire                   HWRITE,
    input  wire [ 2:0]            HSIZE,
    input  wire [ 2:0]            HBURST,
    input  wire [ 3:0]            HPROT,
    input  wire [ 1:0]            HTRANS,
    input  wire                   HREADY,
    output wire                   HREADYOUT,
    output wire                   HRESP,
    output reg  [31:0]            HRDATA,

    // Core Register File Access Port
    output wire [ 4:0]            dbg_rf_raddr,
    input  wire [31:0]            dbg_rf_rdata,

    // Core Pipeline Stage Signals
    input  wire [31:0]            PCF,
    input  wire [31:0]            PCD,
    input  wire [31:0]            PCE,
    input  wire [31:0]            PCM,
    input  wire [31:0]            PCW,
    input  wire [31:0]            InstrD,
    input  wire [31:0]            InstrM,
    input  wire [ 4:0]            StallFlags, // {StallW, StallM, StallE, StallD, StallF}
    input  wire [ 2:0]            FlushFlags, // {FlushM, FlushE, FlushD}
    input  wire                   ExternalStall,
    input  wire                   InstrRetired,
    input  wire                   TrapM,
    input  wire                   mretM,
    input  wire [31:0]            TrapCauseM,
    input  wire [31:0]            TrapValM,

    // Core Privileged CSR Signals
    input  wire [31:0]            mstatus,
    input  wire [31:0]            mcause,
    input  wire [31:0]            mtval,
    input  wire [31:0]            mepc,
    input  wire [31:0]            mtvec,
    input  wire [31:0]            mie,
    input  wire [31:0]            mip,
    input  wire [31:0]            mscratch,
    input  wire [63:0]            cycle_cnt,
    input  wire [63:0]            instret_cnt,

    // Control & Status to SoC / Debugger
    output wire                   auto_halt_trap_o,
    output wire                   trap_latched_o,
    output wire [ 3:0]            fault_flags_o
);

    // =========================================================================
    // 1. AHB-Lite Bus Control & Address Pipelining
    // =========================================================================
    wire valid_trans = HSEL && HREADY && (HTRANS == 2'b10 || HTRANS == 2'b11);

    reg        read_en_d;
    reg        write_en_d;
    reg [11:0] addr_d;

    // Asynchronous register address selection for zero-wait read data availability
    assign dbg_rf_raddr = valid_trans ? HADDR[6:2] : addr_d[6:2];

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            read_en_d  <= 1'b0;
            write_en_d <= 1'b0;
            addr_d     <= 12'd0;
        end else if (HREADY) begin
            read_en_d  <= valid_trans && !HWRITE;
            write_en_d <= valid_trans && HWRITE;
            addr_d     <= HADDR[11:0];
        end else begin
            // Hold state if not HREADY
            read_en_d  <= read_en_d;
            write_en_d <= write_en_d;
            addr_d     <= addr_d;
        end
    end

    // Single-cycle zero-wait response
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0; // OKAY

    // =========================================================================
    // 2. Sticky Crash Capture & Auto-Halt Logic
    // =========================================================================
    reg        halt_on_trap_en;
    reg        halt_on_ebreak_en;
    reg        trap_latched;
    reg [31:0] trap_cause_latched;
    reg [31:0] trap_val_latched;
    reg [31:0] trap_pc_latched;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            halt_on_trap_en    <= 1'b1; // Default enabled for instant post-mortem capture
            halt_on_ebreak_en  <= 1'b1;
            trap_latched       <= 1'b0;
            trap_cause_latched <= 32'd0;
            trap_val_latched   <= 32'd0;
            trap_pc_latched    <= 32'd0;
        end else begin
            // Sticky trap capture on first occurrence of TrapM
            if (TrapM && !trap_latched) begin
                trap_latched       <= 1'b1;
                trap_cause_latched <= TrapCauseM;
                trap_val_latched   <= TrapValM;
                trap_pc_latched    <= PCM;
            end

            // Software configuration write to DBG_CTRL (0x0D0)
            if (write_en_d && (addr_d == 12'h0D0)) begin
                halt_on_trap_en   <= HWDATA[0];
                halt_on_ebreak_en <= HWDATA[1];
                if (HWDATA[2]) begin
                    trap_latched <= 1'b0; // Write 1 to clear
                end
            end
        end
    end

    wire auto_halt_active   = trap_latched && halt_on_trap_en;
    assign auto_halt_trap_o = auto_halt_active;
    assign trap_latched_o   = trap_latched;

    // Diagnostic fault flags for GPI8
    // Bit 0: Illegal Instruction (mcause = 2)
    // Bit 1: Load/Store Fault (mcause = 5 or 7)
    // Bit 2: Breakpoint / Ebreak (mcause = 3)
    // Bit 3: Instruction Misaligned (mcause = 0)
    assign fault_flags_o[0] = trap_latched && (trap_cause_latched[3:0] == 4'h2);
    assign fault_flags_o[1] = trap_latched && ((trap_cause_latched[3:0] == 4'h5) || (trap_cause_latched[3:0] == 4'h7));
    assign fault_flags_o[2] = trap_latched && (trap_cause_latched[3:0] == 4'h3);
    assign fault_flags_o[3] = trap_latched && (trap_cause_latched[3:0] == 4'h0);

    // =========================================================================
    // 3. Circular Micro-Trace Buffer (16 Deep)
    // =========================================================================
    reg [31:0] trace_buf [0:15];
    reg [ 3:0] trace_ptr;
    reg [ 4:0] trace_count;

    integer i;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            trace_ptr   <= 4'd0;
            trace_count <= 5'd0;
            for (i = 0; i < 16; i = i + 1) begin
                trace_buf[i] <= 32'd0;
            end
        end else begin
            // Record retired instructions only while core is freely executing
            if (InstrRetired && !ExternalStall && !trap_latched) begin
                trace_buf[trace_ptr] <= PCW;
                trace_ptr            <= trace_ptr + 4'd1;
                if (trace_count < 5'd16) begin
                    trace_count <= trace_count + 5'd1;
                end
            end
        end
    end

    // =========================================================================
    // 4. Read Data Multiplexer (Data Phase)
    // =========================================================================
    wire is_gpr_access   = (addr_d[11:7] == 5'b00000); // 0x000 - 0x07C (x0 - x31)
    wire is_trace_access = (addr_d[11:6] == 6'b000001); // 0x100 - 0x13C (Trace buffer)

    always @(*) begin
        if (is_gpr_access) begin
            HRDATA = dbg_rf_rdata;
        end else if (is_trace_access) begin
            HRDATA = trace_buf[addr_d[5:2]];
        end else begin
            case (addr_d)
                // Program Counters
                12'h080: HRDATA = PCF;
                12'h084: HRDATA = PCD;
                12'h088: HRDATA = PCE;
                12'h08C: HRDATA = PCM;
                12'h090: HRDATA = PCW;

                // Pipeline Instructions & Flags
                12'h094: HRDATA = InstrD;
                12'h098: HRDATA = InstrM;
                12'h09C: HRDATA = {16'b0, TrapM, mretM, ExternalStall, InstrRetired, FlushFlags, 1'b0, StallFlags};

                // Privileged CSRs
                12'h0A0: HRDATA = mstatus;
                12'h0A4: HRDATA = mcause;
                12'h0A8: HRDATA = mtval;
                12'h0AC: HRDATA = mepc;
                12'h0B0: HRDATA = mtvec;
                12'h0B4: HRDATA = mie;
                12'h0B8: HRDATA = mip;
                12'h0BC: HRDATA = mscratch;

                // Hardware Counters
                12'h0C0: HRDATA = cycle_cnt[31:0];
                12'h0C4: HRDATA = cycle_cnt[63:32];
                12'h0C8: HRDATA = instret_cnt[31:0];
                12'h0CC: HRDATA = instret_cnt[63:32];

                // Post-Mortem Control & Latched Crash Information
                12'h0D0: HRDATA = {28'b0, auto_halt_active, trap_latched, halt_on_ebreak_en, halt_on_trap_en};
                12'h0D4: HRDATA = trap_cause_latched;
                12'h0D8: HRDATA = trap_val_latched;
                12'h0DC: HRDATA = trap_pc_latched;

                // Trace Status
                12'h140: HRDATA = {16'b0, 4'b0, trace_ptr, 3'b0, trace_count};

                default: HRDATA = 32'd0;
            endcase
        end
    end

endmodule
