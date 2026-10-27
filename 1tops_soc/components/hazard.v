// =============================================================================
// Module: hazard
// Purpose: Pipeline Hazard Detection with Forwarding and Full-Pipeline AHB Stalls
// Reference: cvw/1tops_soc/src/hazard/hazard.sv
// =============================================================================

module hazard (
    input  [4:0] Rs1D, Rs2D,
    input  [4:0] Rs1E, Rs2E, RdE,
    input  [4:0] RdM, RdW,
    input        RegWriteM, RegWriteW,
    input  [2:0] ResultSrcE,
    input        PCSrcE,
    input        TrapM,
    input        mretM,

    // AHB Wait-State Stall Inputs from EBU
    input        LSUStallM,
    input        IFUStallF,

    // External Stall from Debugger / Step Controller
    input        ExternalStall,

    // Forwarding Controls
    output reg [1:0] ForwardAE, ForwardBE,

    // Global Pipeline Stall Controls
    output       StallF,
    output       StallD,
    output       StallE,
    output       StallM,
    output       StallW,

    // Pipeline Flush Controls
    output       FlushD,
    output       FlushE,
    output       FlushM
);

    // Forwarding to SrcAE
    always @(*) begin
        if ((Rs1E == RdM) && RegWriteM && (Rs1E != 5'd0))
            ForwardAE = 2'b10; // Forward from Memory stage
        else if ((Rs1E == RdW) && RegWriteW && (Rs1E != 5'd0))
            ForwardAE = 2'b01; // Forward from Writeback stage
        else
            ForwardAE = 2'b00; // No forwarding
    end

    // Forwarding to SrcBE
    always @(*) begin
        if ((Rs2E == RdM) && RegWriteM && (Rs2E != 5'd0))
            ForwardBE = 2'b10; // Forward from Memory stage
        else if ((Rs2E == RdW) && RegWriteW && (Rs2E != 5'd0))
            ForwardBE = 2'b01; // Forward from Writeback stage
        else
            ForwardBE = 2'b00; // No forwarding
    end

    // Load-Use Data Hazard (only active for memory load: ResultSrcE == 3'b001)
    wire lwStall = (ResultSrcE == 3'b001) & ((Rs1D == RdE) | (Rs2D == RdE)) & (RdE != 5'd0);

    // Full Pipeline Stall Cascade for AHB Wait-States:
    // If LSU is waiting for memory/peripheral, freeze the entire machine.
    // If IFU is waiting for instruction fetch, freeze Fetch and Decode.
    // A pipeline flush (branch, jump, trap) overrides IFU fetch stalls so PC can be redirected.
    wire FlushCause = PCSrcE || TrapM || mretM;

    assign StallW = LSUStallM | ExternalStall;
    assign StallM = LSUStallM | ExternalStall;
    assign StallE = LSUStallM | ExternalStall;
    assign StallD = LSUStallM | (lwStall & ~FlushCause) | ExternalStall;
    assign StallF = LSUStallM | ((IFUStallF | lwStall) & ~FlushCause) | ExternalStall;

    // Pipeline Flushes (Gated during bus wait-states and external debugger freeze)
    assign FlushD = (!LSUStallM) && (!ExternalStall) && FlushCause;
    assign FlushE = (!LSUStallM) && (!ExternalStall) && (lwStall || FlushCause);
    assign FlushM = (!LSUStallM) && (!ExternalStall) && (TrapM || mretM);

endmodule
