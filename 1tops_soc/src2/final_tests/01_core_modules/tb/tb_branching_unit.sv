`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_branching_unit.sv
// Purpose: Exhaustive verification of Branching Unit decisions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
// =============================================================================

module tb_branching_unit;

    reg  [2:0] funct3;
    reg        Zero, Less, LessU;
    wire       Branch;

    branching_unit dut (
        .funct3(funct3),
        .Zero(Zero),
        .Less(Less),
        .LessU(LessU),
        .Branch(Branch)
    );

    integer errors = 0;

    task check_branch(
        input [2:0] f3,
        input z, input l, input lu,
        input exp_b,
        input [64*8:1] desc
    );
        begin
            funct3 = f3;
            Zero   = z;
            Less   = l;
            LessU  = lu;
            #1;
            if (Branch !== exp_b) begin
                $display("[FAIL] %0s: funct3=%b, Z=%b, L=%b, LU=%b => Branch=%b (exp %b)",
                         desc, f3, z, l, lu, Branch, exp_b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== Running Branching Unit Verification ===");

        // BEQ (3'b000)
        check_branch(3'b000, 1'b1, 1'b0, 1'b0, 1'b1, "BEQ True (Equal)");
        check_branch(3'b000, 1'b0, 1'b0, 1'b0, 1'b0, "BEQ False (Not Equal)");

        // BNE (3'b001)
        check_branch(3'b001, 1'b0, 1'b0, 1'b0, 1'b1, "BNE True (Not Equal)");
        check_branch(3'b001, 1'b1, 1'b0, 1'b0, 1'b0, "BNE False (Equal)");

        // BLT (3'b100) - Signed
        check_branch(3'b100, 1'b0, 1'b1, 1'b0, 1'b1, "BLT True (Signed Less)");
        check_branch(3'b100, 1'b0, 1'b0, 1'b0, 1'b0, "BLT False (Signed Greater/Equal)");

        // BGE (3'b101) - Signed
        check_branch(3'b101, 1'b0, 1'b0, 1'b0, 1'b1, "BGE True (Signed Greater/Equal)");
        check_branch(3'b101, 1'b0, 1'b1, 1'b0, 1'b0, "BGE False (Signed Less)");

        // BLTU (3'b110) - Unsigned
        check_branch(3'b110, 1'b0, 1'b0, 1'b1, 1'b1, "BLTU True (Unsigned Less)");
        check_branch(3'b110, 1'b0, 1'b0, 1'b0, 1'b0, "BLTU False (Unsigned Greater/Equal)");

        // BGEU (3'b111) - Unsigned
        check_branch(3'b111, 1'b0, 1'b0, 1'b0, 1'b1, "BGEU True (Unsigned Greater/Equal)");
        check_branch(3'b111, 1'b0, 1'b0, 1'b1, 1'b0, "BGEU False (Unsigned Less)");

        if (errors == 0) begin
            $display("[TB] Test Result: PASSED! (0 errors across all branch conditions)");
        end else begin
            $display("[TB] Test Result: FAILED with %0d errors!", errors);
        end
        $finish;
    end

endmodule
