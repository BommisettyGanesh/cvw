`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_multiplier_ahb.sv
// Purpose: Verification of AHB Hardware Multiplier Accelerator (multiplier_ahb.v)
// =============================================================================

module tb_multiplier_ahb;

    localparam XLEN = 32;

    reg             clk;
    reg             reset;
    reg             HSEL;
    reg  [XLEN-1:0] HADDR;
    reg  [XLEN-1:0] HWDATA;
    reg             HWRITE;
    reg  [ 2:0]     HSIZE;
    reg  [ 2:0]     HBURST;
    reg  [ 3:0]     HPROT;
    reg  [ 1:0]     HTRANS;
    reg             HREADY;
    wire            HREADYOUT;
    wire            HRESP;
    wire [XLEN-1:0] HRDATA;

    // Clock generator (50 MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // DUT Instantiation
    multiplier_ahb #(
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .reset(reset),
        .HSEL(HSEL),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HREADY(HREADY),
        .HREADYOUT(HREADYOUT),
        .HRESP(HRESP),
        .HRDATA(HRDATA)
    );

    int pass_count = 0;
    int fail_count = 0;

    // Reset task
    task automatic reset_dut();
        reset  = 1;
        HSEL   = 0;
        HADDR  = 0;
        HWDATA = 0;
        HWRITE = 0;
        HSIZE  = 3'b010;
        HBURST = 3'b000;
        HPROT  = 4'b0011;
        HTRANS = 2'b00;
        HREADY = 1;
        repeat(5) @(posedge clk);
        reset  = 0;
        @(posedge clk);
        #1;
    endtask

    // AHB Single Write Task
    task automatic ahb_write(input bit [31:0] addr, input bit [31:0] data);
        @(posedge clk);
        HSEL   = 1'b1;
        HADDR  = addr;
        HWRITE = 1'b1;
        HTRANS = 2'b10; // NONSEQ

        @(posedge clk);
        HWDATA = data;
        HSEL   = 1'b0;
        HTRANS = 2'b00; // IDLE

        @(posedge clk);
        #1;
    endtask

    // AHB Single Read Task
    task automatic ahb_read(input bit [31:0] addr, output bit [31:0] data);
        @(posedge clk);
        HSEL   = 1'b1;
        HADDR  = addr;
        HWRITE = 1'b0;
        HTRANS = 2'b10; // NONSEQ

        @(posedge clk);
        #1;
        data   = HRDATA; // Sample during active data phase
        HSEL   = 1'b0;
        HTRANS = 2'b00; // IDLE
    endtask

    // Multiplication Verification Task
    task automatic verify_multiplication(input bit [31:0] a, input bit [31:0] b);
        bit [31:0] expected_product;
        bit [31:0] actual_product;
        bit [31:0] read_a, read_b;

        expected_product = a * b;

        // Write Operand A
        ahb_write(32'h3000_0000, a);
        // Write Operand B
        ahb_write(32'h3000_0004, b);

        // Read Operand A & B back
        ahb_read(32'h3000_0000, read_a);
        ahb_read(32'h3000_0004, read_b);

        if (read_a !== a) begin
            $display("[FAIL] Operand A read mismatch! Exp: 0x%08x, Got: 0x%08x", a, read_a);
            fail_count++;
        end else begin
            pass_count++;
        end

        if (read_b !== b) begin
            $display("[FAIL] Operand B read mismatch! Exp: 0x%08x, Got: 0x%08x", b, read_b);
            fail_count++;
        end else begin
            pass_count++;
        end

        // Read Product
        ahb_read(32'h3000_0008, actual_product);

        if (actual_product !== expected_product) begin
            $display("[FAIL] Product mismatch! %0d * %0d = exp: 0x%08x, got: 0x%08x", a, b, expected_product, actual_product);
            fail_count++;
        end else begin
            pass_count++;
        end
    endtask

    initial begin
        bit [31:0] rand_a, rand_b;

        $display("================================================================");
        $display("   TESTBENCH: AHB Hardware Multiplier Accelerator               ");
        $display("================================================================");

        reset_dut();

        // 1. Directed Test: Small positive numbers
        $display("[TEST 1] Small positive multiplication (12 * 34)...");
        verify_multiplication(32'd12, 32'd34);

        // 2. Directed Test: Large numbers
        $display("[TEST 2] Medium values (0x1234 * 0x5678)...");
        verify_multiplication(32'h1234, 32'h5678);

        // 3. Directed Test: Zero and Identity
        $display("[TEST 3] Zero and Identity multiplications...");
        verify_multiplication(32'd0, 32'd9999);
        verify_multiplication(32'd1, 32'hDEADBEEF);

        // 4. Directed Test: Negative / 2's complement values
        $display("[TEST 4] Signed 2's complement values (-10 * 25)...");
        verify_multiplication(-32'd10, 32'd25);

        // 5. Constrained-Random Test Suite (50 iterations)
        $display("[TEST 5] Constrained-Random Multiplications (50 iterations)...");
        for (int i = 0; i < 50; i++) begin
            rand_a = $urandom();
            rand_b = $urandom();
            verify_multiplication(rand_a, rand_b);
        end

        // Summary
        $display("================================================================");
        $display("   MULTIPLIER RESULTS: %0d CHECKS PASSED, %0d FAILED", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL AHB MULTIPLIER ACCELERATOR TESTS PASSED! <<<");
            $finish(0);
        end else begin
            $display(">>> AHB MULTIPLIER ACCELERATOR TESTS FAILED! <<<");
            $fatal(1, "Verification errors encountered");
        end
    end

endmodule
