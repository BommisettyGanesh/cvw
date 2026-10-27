`timescale 1ns/1ps

// =============================================================================
// Module: core_invariants_checker
// Purpose: Formal SystemVerilog Assertions (SVA) for Processor Pipeline Invariants
// =============================================================================

module core_invariants_checker (
    input             clk,
    input             reset,
    input      [31:0] PC,
    input      [31:0] PCW,
    input             RegWriteW,
    input      [ 4:0] RdW,
    input      [31:0] ResultW,
    input      [ 1:0] ForwardAE,
    input      [ 1:0] ForwardBE,
    input             FlushD,
    input             FlushE,
    input             TrapM,
    input      [31:0] mtvec,

    // Debugger Subsystem Feature Signals
    input             ExternalStall,
    input             StallF,
    input             StallD,
    input             StallE,
    input             StallM,
    input             StallW,
    input             InstrRetired,
    input             dbg_core_reset,
    input             core_HRESETn
);

    // 1. Word alignment of PC
    property p_pc_aligned;
        @(posedge clk) disable iff (reset)
        (PC[1:0] == 2'b00);
    endproperty
    assert property (p_pc_aligned)
        else $error("[CORE INVARIANT ERROR] Misaligned PC = 0x%08x at time %0t!", PC, $time);

    // 2. Valid range for forwarding multiplexer select lines
    property p_forwarding_valid;
        @(posedge clk) disable iff (reset)
        (ForwardAE <= 2'b10) && (ForwardBE <= 2'b10);
    endproperty
    assert property (p_forwarding_valid)
        else $error("[CORE INVARIANT ERROR] Invalid forwarding select: ForwardAE=%b, ForwardBE=%b at time %0t!", ForwardAE, ForwardBE, $time);

    // 3. Trap entry redirects PC to mtvec base address
    property p_trap_redirection;
        @(posedge clk) disable iff (reset)
        TrapM |=> (PC[31:2] == mtvec[31:2]);
    endproperty
    assert property (p_trap_redirection)
        else $error("[CORE INVARIANT ERROR] Trap occurred but PC (0x%08x) did not branch to mtvec (0x%08x) at time %0t!", PC, mtvec, $time);

    // 4. ExternalStall freezes entire 5-stage pipeline
    property p_external_stall_freezes_all;
        @(posedge clk) disable iff (reset)
        ExternalStall |-> (StallF && StallD && StallE && StallM && StallW);
    endproperty
    assert property (p_external_stall_freezes_all)
        else $error("[CORE INVARIANT ERROR] ExternalStall asserted but not all stages stalled at time %0t!", $time);

    // 5. InstrRetired is never asserted during a stall or trap
    property p_instr_retired_clean;
        @(posedge clk) disable iff (reset)
        InstrRetired |-> (!StallW && !TrapM);
    endproperty
    assert property (p_instr_retired_clean)
        else $error("[CORE INVARIANT ERROR] InstrRetired asserted during stall (StallW=%b) or trap (TrapM=%b) at time %0t!", StallW, TrapM, $time);

    // 6. Debugger core reset forces core_HRESETn active low
    property p_dbg_core_reset_active;
        @(posedge clk)
        dbg_core_reset |-> (!core_HRESETn);
    endproperty
    assert property (p_dbg_core_reset_active)
        else $error("[CORE INVARIANT ERROR] dbg_core_reset asserted but core_HRESETn not 0 at time %0t!", $time);

endmodule
