`timescale 1ns/1ps

// =============================================================================
// Module: watchdog
// Source Reference: OpenHW Group CORE-V-WALLY (cvw) testbench/common/watchdog.sv
// Purpose: Signal-level monitor that detects processor hangs (infinite pipeline
//          stalls / frozen PCW) and recursive trap livelocks (infinite loop
//          trapping at identical PCM).
// =============================================================================

module watchdog #(
    parameter XLEN = 32,
    parameter WatchDogTimerThreshold = 5000,
    parameter SameTrapPCThreshold = 50
)(
    input              clk,
    input              reset,
    input  [XLEN-1:0]  PCW,
    input              TrapM,
    input  [XLEN-1:0]  PCM,
    input  string      TEST_NAME
);

    // 1. Stuck PCW detection (hang / infinite stall without retiring instructions)
    logic [XLEN-1:0] OldPCW;
    integer          WatchDogTimerCount;
    logic            WatchDogTimeOut;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            OldPCW             <= '0;
            WatchDogTimerCount <= 0;
        end else begin
            OldPCW <= PCW;
            if (OldPCW == PCW && PCW != '0) begin
                WatchDogTimerCount <= WatchDogTimerCount + 1;
            end else begin
                WatchDogTimerCount <= 0;
            end
        end
    end

    // 2. Recursive Trap Livelock detection (faulting handler re-traps identically)
    logic [XLEN-1:0] LastTrapPC;
    integer          SameTrapPCCount;
    logic            TrapMD;
    wire             TrapEvent = TrapM & ~TrapMD; // One pulse per trap occurrence

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            TrapMD          <= 1'b0;
            LastTrapPC      <= '0;
            SameTrapPCCount <= 0;
        end else begin
            TrapMD <= TrapM;
            if (TrapEvent) begin
                if (PCM == LastTrapPC && PCM != '0) begin
                    SameTrapPCCount <= SameTrapPCCount + 1;
                end else begin
                    SameTrapPCCount <= 0;
                end
                LastTrapPC <= PCM;
            end
        end
    end

    // 3. Timeout evaluation and assertion reporting
    assign WatchDogTimeOut   = (WatchDogTimerCount >= WatchDogTimerThreshold);
    assign SameTrapPCTimeOut = (SameTrapPCCount >= SameTrapPCThreshold);

    always_ff @(posedge clk) begin
        if (!reset) begin
            if (WatchDogTimeOut) begin
                $display("\n=======================================================");
                $display("[WATCHDOG TIMEOUT ERROR] Test: %s", TEST_NAME);
                $display("Processor stalled! PCW stuck at 0x%08x for %0d cycles.", PCW, WatchDogTimerCount);
                $display("=======================================================\n");
                $fatal(1, "Processor hang detected by watchdog.");
            end

            if (SameTrapPCTimeOut) begin
                $display("\n=======================================================");
                $display("[WATCHDOG RECURSIVE TRAP ERROR] Test: %s", TEST_NAME);
                $display("Recursive trap livelock detected! PCM 0x%08x trapped %0d times consecutively.", 
                         LastTrapPC, SameTrapPCCount);
                $display("=======================================================\n");
                $fatal(1, "Recursive trap livelock detected by watchdog.");
            end
        end
    end

endmodule
