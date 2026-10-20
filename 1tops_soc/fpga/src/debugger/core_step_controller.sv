//-----------------------------------------------------------------------------
// Module: core_step_controller
// Project: CORE-V Wally RISC-V SoC (1tops_soc)
//
// Description:
//   Deterministic Core Single-Step Execution Controller for CORE-V Wally.
//   Bridges the SoCDebug subsystem (UART / FT1248) and the CPU Hazard Unit.
//
// Features:
//   1. Instruction Stepping (step_mode_i = 0):
//      Deasserts ExternalStall until exactly ONE instruction commits in the core
//      (instr_retired_i = 1), then immediately re-freezes the pipeline.
//   2. Clock-Cycle Stepping (step_mode_i = 1):
//      Deasserts ExternalStall for exactly ONE clock cycle, advancing the pipeline
//      by 1 cycle, then immediately re-freezes.
//   3. Glitch-Free Synchronous Edge Detection:
//      Triggers stepping on rising edge of step_req_i (GPO8[2]), preventing runaway
//      execution if the register bit remains set.
//   4. Safety Watchdog Timeout:
//      In Instruction Step mode, if the pipeline stalls for more than WATCHDOG_LIMIT
//      cycles (e.g. hung bus, deadlock, or unhandled loop), the controller automatically
//      re-asserts stall and reports completion/timeout, preventing debugger freeze.
//   5. Status Feedback:
//      Drives step_busy_o (GPI8[1]) and step_done_o (GPI8[2]) for host polling.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module core_step_controller #(
    parameter int WATCHDOG_LIMIT = 65536 // Max cycles before auto-timeout on instruction step
)(
    input  wire        clk,
    input  wire        rst_n,

    // Debugger Control Inputs (from GPO8)
    input  wire        halt_req_i,       // GPO8[1]: 1 = Core Halt requested, 0 = Core Free Run
    input  wire        step_req_i,       // GPO8[2]: 0->1 transition triggers a step
    input  wire        step_mode_i,      // GPO8[3]: 0 = Instruction Step, 1 = Clock Cycle Step

    // Core Status / Feedback Inputs
    input  wire        instr_retired_i,  // 1-cycle strobe from CPU core when instruction retires
    input  wire        core_stall_ext_i, // Additional external stall (e.g. from top-level pin)

    // Pipeline Control & Status Outputs
    output reg         core_stall_o,     // Drives ExternalStall of wallypipelinedcore / hazard.sv
    output reg         step_busy_o,      // High while a step is executing (fed to GPI8[1])
    output reg         step_done_o,      // 1-cycle strobe upon step completion (fed to GPI8[2])
    output reg [31:0]  step_count_o      // Diagnostic counter of total steps executed
);

    // State Encoding
    typedef enum logic [1:0] {
        STATE_RUN      = 2'b00, // Core is running freely (halt_req_i == 0)
        STATE_HALTED   = 2'b01, // Core is halted/frozen (ExternalStall == 1)
        STATE_STEPPING = 2'b10, // Core is unstalled, executing 1 step
        STATE_DONE     = 2'b11  // Step finished, re-freezing pipeline and signaling completion
    } state_t;

    state_t state, next_state;

    // Edge detector for step_req_i
    reg step_req_d;
    wire step_trigger = step_req_i & (~step_req_d);

    // Watchdog counter to avoid deadlock in instruction step mode
    reg [23:0] watchdog_cnt;

    // Synchronous edge detection flip-flop
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_req_d <= 1'b0;
        end else begin
            step_req_d <= step_req_i;
        end
    end

    // Sequential State Register & Counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_RUN;
            step_count_o <= 32'd0;
            watchdog_cnt <= 24'd0;
        end else begin
            state <= next_state;

            // Step counter
            if (state == STATE_STEPPING && next_state == STATE_DONE) begin
                step_count_o <= step_count_o + 32'd1;
            end

            // Watchdog counter
            if (state == STATE_STEPPING) begin
                watchdog_cnt <= watchdog_cnt + 24'd1;
            end else begin
                watchdog_cnt <= 24'd0;
            end
        end
    end

    // Next-State Logic
    always_comb begin
        next_state = state;

        case (state)
            STATE_RUN: begin
                // Transition to halted when debugger asserts halt_req_i
                if (halt_req_i) begin
                    next_state = STATE_HALTED;
                end
            end

            STATE_HALTED: begin
                if (!halt_req_i) begin
                    // Host released halt -> resume free execution
                    next_state = STATE_RUN;
                end else if (step_trigger) begin
                    // Host triggered a step while halted
                    next_state = STATE_STEPPING;
                end
            end

            STATE_STEPPING: begin
                if (!halt_req_i) begin
                    // User aborted halt during stepping
                    next_state = STATE_RUN;
                end else if (step_mode_i == 1'b1) begin
                    // Cycle Step: Exactly 1 clock cycle of unhalted execution
                    next_state = STATE_DONE;
                end else begin
                    // Instruction Step: Wait for instruction retirement or safety timeout
                    if (instr_retired_i || (watchdog_cnt >= WATCHDOG_LIMIT - 1)) begin
                        next_state = STATE_DONE;
                    end
                end
            end

            STATE_DONE: begin
                // Return to halted state (re-freezing pipeline)
                if (!halt_req_i) begin
                    next_state = STATE_RUN;
                end else begin
                    next_state = STATE_HALTED;
                end
            end

            default: next_state = STATE_RUN;
        endcase
    end

    // Output Logic
    always_comb begin
        case (state)
            STATE_RUN: begin
                core_stall_o = core_stall_ext_i;
                step_busy_o  = 1'b0;
                step_done_o  = 1'b0;
            end

            STATE_HALTED: begin
                core_stall_o = 1'b1; // Freeze pipeline
                step_busy_o  = 1'b0;
                step_done_o  = 1'b0;
            end

            STATE_STEPPING: begin
                // Temporarily release stall to let pipeline advance
                core_stall_o = core_stall_ext_i;
                step_busy_o  = 1'b1;
                step_done_o  = 1'b0;
            end

            STATE_DONE: begin
                // Immediately re-assert stall on the cycle after retirement
                core_stall_o = 1'b1;
                step_busy_o  = 1'b0;
                step_done_o  = 1'b1; // 1-cycle completion pulse
            end

            default: begin
                core_stall_o = core_stall_ext_i;
                step_busy_o  = 1'b0;
                step_done_o  = 1'b0;
            end
        endcase
    end

endmodule
