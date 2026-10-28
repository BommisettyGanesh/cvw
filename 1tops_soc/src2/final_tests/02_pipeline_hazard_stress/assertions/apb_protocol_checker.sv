`timescale 1ns/1ps

// =============================================================================
// Module: apb_protocol_checker
// Purpose: Formal SystemVerilog Assertions (SVA) for APB Bridge & Peripheral Transfers
// =============================================================================

module apb_protocol_checker (
    input             PCLK,
    input             PRESETn,
    input             PSEL,
    input             PENABLE,
    input      [31:0] PADDR,
    input             PWRITE,
    input      [31:0] PWDATA,
    input             PREADY,
    input      [ 3:0] PSEL_PERIPHERALS
);

    // 1. APB State Transition: PENABLE follows PSEL
    property p_penable_after_psel;
        @(posedge PCLK) disable iff (!PRESETn)
        ($rose(PSEL) && !PENABLE) |=> PENABLE;
    endproperty
    assert property (p_penable_after_psel)
        else $error("[SVA APB ERROR] PENABLE did not assert cycle after PSEL at time %0t!", $time);

    // 2. Address & Control Stability during ACCESS phase (PENABLE high)
    property p_apb_addr_ctrl_stability;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> ($stable(PADDR) && $stable(PWRITE) && $stable(PWDATA));
    endproperty
    assert property (p_apb_addr_ctrl_stability)
        else $error("[SVA APB ERROR] PADDR, PWRITE, or PWDATA changed while PENABLE was waiting for PREADY at time %0t!", $time);

    // 3. One-hot peripheral selection
    property p_onehot_peripheral;
        @(posedge PCLK) disable iff (!PRESETn)
        $onehot0(PSEL_PERIPHERALS);
    endproperty
    assert property (p_onehot_peripheral)
        else $error("[SVA APB ERROR] Multiple APB peripherals selected simultaneously: PSEL = %b at time %0t!", PSEL_PERIPHERALS, $time);

endmodule
