`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_ahb_apb_bridge_crv.sv
// Purpose: AMBA 3 AHB-Lite to APB 3 Bridge (ahbapbbridge.v) Verification
//          Verifies Setup phase, Access phase, Wait-states, and Multiplexing.
// =============================================================================

module tb_ahb_apb_bridge_crv;

    localparam XLEN    = 32;
    localparam PERIPHS = 4;

    reg                 HCLK;
    reg                 HRESETn;
    reg  [PERIPHS-1:0]  HSEL;
    reg  [31:0]         HADDR;
    reg  [XLEN-1:0]     HWDATA;
    reg  [XLEN/8-1:0]   HWSTRB;
    reg                 HWRITE;
    reg  [ 1:0]         HTRANS;
    wire                HREADY;
    wire [XLEN-1:0]     HRDATA;
    wire                HRESP;
    wire                HREADYOUT;

    wire                PCLK;
    wire                PRESETn;
    wire [PERIPHS-1:0]  PSEL;
    wire                PWRITE;
    wire                PENABLE;
    wire [31:0]         PADDR;
    wire [XLEN-1:0]     PWDATA;
    wire [XLEN/8-1:0]   PSTRB;
    reg  [PERIPHS-1:0]  PREADY;
    reg  [PERIPHS*XLEN-1:0] PRDATA;

    // Bus HREADY feedback from bridge HREADYOUT
    assign HREADY = HREADYOUT;

    // Clock Generation (50 MHz)
    initial HCLK = 0;
    always #10 HCLK = ~HCLK;

    // DUT Instantiation
    ahbapbbridge #(
        .XLEN(XLEN),
        .PERIPHS(PERIPHS)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSEL(HSEL),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HWRITE(HWRITE),
        .HTRANS(HTRANS),
        .HREADY(HREADY),
        .HRDATA(HRDATA),
        .HRESP(HRESP),
        .HREADYOUT(HREADYOUT),

        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PWRITE(PWRITE),
        .PENABLE(PENABLE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PSTRB(PSTRB),
        .PREADY(PREADY),
        .PRDATA(PRDATA)
    );

    // Global Test Counters
    int pass_count = 0;
    int fail_count = 0;

    // Reset DUT
    task automatic reset_dut();
        HRESETn = 0;
        HSEL    = 0;
        HADDR   = 0;
        HWDATA  = 0;
        HWSTRB  = 0;
        HWRITE  = 0;
        HTRANS  = 2'b00; // IDLE
        PREADY  = {PERIPHS{1'b1}};
        PRDATA  = 0;
        repeat(5) @(posedge HCLK);
        HRESETn = 1;
        @(posedge HCLK);
        $display("[INFO] Reset deasserted successfully.");
    endtask

    // AHB Master Driver Task
    task automatic run_transfer(
        input int periph_id,
        input bit [31:0] addr,
        input bit [31:0] wdata,
        input bit is_write,
        input int wait_states
    );
        bit [31:0] exp_rdata;
        exp_rdata = 32'hBEEF0000 | (periph_id << 12) | (addr[11:0]);
        PRDATA[periph_id*32 +: 32] = exp_rdata;

        // 1. AHB Address Phase
        @(posedge HCLK);
        HSEL   = (1 << periph_id);
        HADDR  = addr;
        HWRITE = is_write;
        HTRANS = 2'b10; // NONSEQ
        HWSTRB = 4'b1111;

        // 2. APB Setup Phase: clock edge registers address & asserts PSEL; HREADYOUT goes LOW
        @(posedge HCLK);
        HWDATA = wdata;
        HSEL   = 0;
        HTRANS = 2'b00; // Next AHB cycle IDLE

        #1; // Allow non-blocking assignments to settle
        if (PSEL[periph_id] !== 1'b1 || PENABLE !== 1'b0 || PADDR !== addr || HREADYOUT !== 1'b0) begin
            $display("[FAIL] APB Setup phase violation! PSEL=%b, PENABLE=%b, HREADYOUT=%b", PSEL, PENABLE, HREADYOUT);
            fail_count++;
        end else begin
            pass_count++;
        end

        // 3. APB Access Phase: clock edge asserts PENABLE
        if (wait_states > 0) begin
            PREADY[periph_id] = 1'b0;
            for (int w = 0; w < wait_states; w++) begin
                @(posedge HCLK);
                #1;
                if (PENABLE !== 1'b1 || HREADYOUT !== 1'b0) begin
                    $display("[FAIL] APB wait state %0d violated! PENABLE=%b, HREADYOUT=%b", w, PENABLE, HREADYOUT);
                    fail_count++;
                end else begin
                    pass_count++;
                end
            end
            PREADY[periph_id] = 1'b1;
            #1; // PREADY asserted during final access cycle
        end else begin
            PREADY[periph_id] = 1'b1;
            @(posedge HCLK);
            #1;
        end

        // Verify Completion
        if (PENABLE !== 1'b1) begin
            $display("[FAIL] PENABLE not asserted at completion!");
            fail_count++;
        end else if (HREADYOUT !== 1'b1) begin
            $display("[FAIL] HREADYOUT not asserted at completion!");
            fail_count++;
        end else begin
            pass_count++;
        end

        // Verify Data
        if (is_write) begin
            if (PWDATA !== wdata) begin
                $display("[FAIL] PWDATA mismatch! Exp: %h, Got: %h", wdata, PWDATA);
                fail_count++;
            end else begin
                pass_count++;
            end
        end else begin
            if (HRDATA !== exp_rdata) begin
                $display("[FAIL] HRDATA mismatch! Exp: %h, Got: %h", exp_rdata, HRDATA);
                fail_count++;
            end else begin
                pass_count++;
            end
        end

        // Return to idle
        @(posedge HCLK);
        #1;
    endtask

    // Main Test Stimulus
    initial begin
        int p_id, w_states;
        bit [31:0] rand_addr, rand_data;
        bit rand_rw;

        $display("================================================================");
        $display("   TESTBENCH: AMBA AHB-Lite to APB Bridge Verification         ");
        $display("================================================================");

        reset_dut();

        // 1. Directed Test: Zero-wait state write to Peripheral 0
        $display("[TEST 1] Directed: Zero-wait state write to Peripheral 0...");
        run_transfer(0, 32'h2000_0000, 32'hA5A5_1234, 1'b1, 0);

        // 2. Directed Test: Zero-wait state read from Peripheral 1
        $display("[TEST 2] Directed: Zero-wait state read from Peripheral 1...");
        run_transfer(1, 32'h2000_1004, 32'h0, 1'b0, 0);

        // 3. Directed Test: 2 wait-states write to Peripheral 2
        $display("[TEST 3] Directed: 2 wait-states write to Peripheral 2...");
        run_transfer(2, 32'h2000_2010, 32'hCAFE_BABE, 1'b1, 2);

        // 4. Directed Test: 3 wait-states read from Peripheral 3
        $display("[TEST 4] Directed: 3 wait-states read from Peripheral 3...");
        run_transfer(3, 32'h2000_3020, 32'h0, 1'b0, 3);

        // 5. Constrained Random Transfer Suite (50 iterations)
        $display("[TEST 5] Constrained-Random Transfers across all peripherals (50 iterations)...");
        for (int i = 0; i < 50; i++) begin
            p_id      = $urandom_range(0, PERIPHS-1);
            rand_addr = ($urandom() & 32'hFFFF_FFF0);
            rand_data = $urandom();
            rand_rw   = $urandom_range(0, 1);
            w_states  = $urandom_range(0, 3);

            run_transfer(p_id, rand_addr, rand_data, rand_rw, w_states);
        end

        // Final Assessment
        $display("================================================================");
        $display("   APB BRIDGE TEST RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL AMBA AHB-TO-APB BRIDGE TESTS PASSED! <<<");
            $finish(0);
        end else begin
            $display(">>> APB BRIDGE VERIFICATION FAILED! <<<");
            $fatal(1, "Verification errors encountered");
        end
    end

endmodule
