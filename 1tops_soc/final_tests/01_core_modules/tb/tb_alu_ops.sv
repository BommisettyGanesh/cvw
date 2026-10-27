`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_alu_ops.sv
// Purpose: Exhaustive self-checking unit verification of RV32 ALU operations
// =============================================================================

module tb_alu_ops;

    reg  [31:0] a, b;
    reg  [ 3:0] alu_ctrl;
    wire [31:0] alu_out;
    wire        zero, less, less_u;

    // Instantiate ALU module under test
    alu dut (
        .a(a),
        .b(b),
        .alu_ctrl(alu_ctrl),
        .alu_out(alu_out),
        .zero(zero),
        .less(less),
        .less_u(less_u)
    );

    integer errors = 0;

    task check_alu(
        input [31:0] in_a,
        input [31:0] in_b,
        input [ 3:0] in_ctrl,
        input [31:0] exp_res,
        input [64*8:1] op_name
    );
        reg exp_zero;
        reg exp_less;
        reg exp_lessu;
        begin
            a = in_a;
            b = in_b;
            alu_ctrl = in_ctrl;
            exp_zero  = (exp_res == 32'd0);
            exp_less  = ($signed(in_a) < $signed(in_b));
            exp_lessu = (in_a < in_b);
            #1;
            if (alu_out !== exp_res || zero !== exp_zero || less !== exp_less || less_u !== exp_lessu) begin
                $display("[FAIL] %0s: A=0x%08x, B=0x%08x => Result=0x%08x (exp 0x%08x), Z=%b (exp %b), L=%b (exp %b), LU=%b (exp %b)",
                         op_name, in_a, in_b, alu_out, exp_res, zero, exp_zero, less, exp_less, less_u, exp_lessu);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== Running ALU Operations Unit Test ===");

        // ADD (ctrl 4'b0000)
        check_alu(32'd15, 32'd27, 4'b0000, 32'd42, "ADD Basic");
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b0000, 32'd0, "ADD Overflow to Zero");

        // SUB (ctrl 4'b0001)
        check_alu(32'd100, 32'd40, 4'b0001, 32'd60, "SUB Positive");
        check_alu(32'd50, 32'd50, 4'b0001, 32'd0, "SUB Equal Zero");
        check_alu(32'd10, 32'd20, 4'b0001, 32'hFFFF_FFF6, "SUB Negative");

        // AND (ctrl 4'b0010)
        check_alu(32'hF0F0_AAAA, 32'h0F0F_5555, 4'b0010, 32'h0000_0000, "AND Disjoint");
        check_alu(32'hFFFF_FFFF, 32'h1234_5678, 4'b0010, 32'h1234_5678, "AND Mask");

        // OR (ctrl 4'b0011)
        check_alu(32'hF0F0_0000, 32'h0F0F_FFFF, 4'b0011, 32'hFFFF_FFFF, "OR Combine");

        // SLL (ctrl 4'b0100)
        check_alu(32'h0000_0001, 32'd4, 4'b0100, 32'h0000_0010, "SLL by 4");

        // SLT (ctrl 4'b0101) - Signed comparison
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b0101, 32'd1, "SLT -1 < 1 (Signed)");
        check_alu(32'd1, 32'hFFFF_FFFF, 4'b0101, 32'd0, "SLT 1 < -1 (Signed)");

        // SLTU (ctrl 4'b0110) - Unsigned comparison
        check_alu(32'd1, 32'hFFFF_FFFF, 4'b0110, 32'd1, "SLTU 1 < 0xFFFFFFFF (Unsigned)");
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b0110, 32'd0, "SLTU 0xFFFFFFFF < 1 (Unsigned)");

        // XOR (ctrl 4'b0111)
        check_alu(32'hAAAA_5555, 32'h5555_AAAA, 4'b0111, 32'hFFFF_FFFF, "XOR Invert");
        check_alu(32'h1234_5678, 32'h1234_5678, 4'b0111, 32'h0000_0000, "XOR Self Zero");

        // SRA (ctrl 4'b1000) - Arithmetic shift right
        check_alu(32'h8000_0000, 32'd4, 4'b1000, 32'hF800_0000, "SRA Arithmetic Right");

        // SRL (ctrl 4'b1001) - Logical shift right
        check_alu(32'h8000_0000, 32'd4, 4'b1001, 32'h0800_0000, "SRL Logical Right");

        if (errors == 0) begin
            $display("[TB] Test Result: PASSED! (0 errors across all ALU operations)");
        end else begin
            $display("[TB] Test Result: FAILED with %0d errors!", errors);
        end
        $finish;
    end

endmodule
