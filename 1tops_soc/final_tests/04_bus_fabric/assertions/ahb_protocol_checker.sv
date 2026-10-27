`timescale 1ns/1ps

// =============================================================================
// Module: ahb_protocol_checker
// Purpose: Formal SystemVerilog Assertions (SVA) for AMBA 3 AHB-Lite Bus Protocol
// =============================================================================

module ahb_protocol_checker (
    input             HCLK,
    input             HRESETn,
    input      [31:0] HADDR,
    input      [31:0] HWDATA,
    input      [ 3:0] HWSTRB,
    input             HWRITE,
    input      [ 2:0] HSIZE,
    input      [ 1:0] HTRANS,
    input      [31:0] HRDATA,
    input             HREADY,
    input             HRESP,
    input      [ 3:0] HSEL_SLAVES
);

    // 1. Address & Control Stability during wait states (HREADY low)
    property p_addr_ctrl_stability;
        @(posedge HCLK) disable iff (!HRESETn)
        (!HREADY && HTRANS != 2'b00) |=> ($stable(HADDR) && $stable(HWRITE) && $stable(HSIZE) && $stable(HTRANS));
    endproperty
    assert property (p_addr_ctrl_stability)
        else $error("[SVA AHB ERROR] HADDR, HWRITE, HSIZE, or HTRANS changed while HREADY was low at time %0t!", $time);

    // 2. Write Data Stability during write wait states
    property p_wdata_stability;
        @(posedge HCLK) disable iff (!HRESETn)
        (!HREADY && $past(HWRITE) && $past(HREADY) == 1'b0) |=> $stable(HWDATA);
    endproperty
    assert property (p_wdata_stability)
        else $error("[SVA AHB ERROR] HWDATA changed during wait states at time %0t!", $time);

    // 3. Mutual exclusion of slave address decoders
    property p_onehot_slave_select;
        @(posedge HCLK) disable iff (!HRESETn)
        $onehot0(HSEL_SLAVES);
    endproperty
    assert property (p_onehot_slave_select)
        else $error("[SVA AHB ERROR] Multiple AHB slaves selected simultaneously: HSEL = %b at time %0t!", HSEL_SLAVES, $time);

    // 4. Known value checks on essential control signals (no 'x' or 'z')
    property p_known_control;
        @(posedge HCLK) disable iff (!HRESETn)
        !$isunknown(HTRANS) && !$isunknown(HWRITE) && !$isunknown(HREADY);
    endproperty
    assert property (p_known_control)
        else $error("[SVA AHB ERROR] Unknown control signal (X/Z detected) at time %0t!", $time);

endmodule
