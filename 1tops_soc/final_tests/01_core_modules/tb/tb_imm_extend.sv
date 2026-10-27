`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_imm_extend.sv
// Purpose: Verification of I, S, B, and J type immediate extension logic
// =============================================================================

module tb_imm_extend;

    reg  [31:0] full_instr;
    reg  [ 1:0] immsrc;
    wire [31:0] immext;

    imm_extend dut (
        .instr(full_instr[31:7]),
        .immsrc(immsrc),
        .immext(immext)
    );

    integer errors = 0;

    task check_imm(
        input [31:0] instr_word,
        input [ 1:0] in_src,
        input [31:0] exp_ext,
        input [64*8:1] desc
    );
        begin
            full_instr = instr_word;
            immsrc     = in_src;
            #1;
            if (immext !== exp_ext) begin
                $display("[FAIL] %0s: instr=0x%08x, immsrc=%b => immext=0x%08x (exp 0x%08x)",
                         desc, instr_word, in_src, immext, exp_ext);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== Running Immediate Extend Unit Verification ===");

        // I-type: addi x1, x0, 10 (0x00A00093) -> imm = +10
        check_imm(32'h00A0_0093, 2'b00, 32'h0000_000A, "I-type Positive (+10)");

        // I-type: addi x1, x0, -1 (0xFFF00093) -> imm = -1
        check_imm(32'hFFF0_0093, 2'b00, 32'hFFFF_FFFF, "I-type Negative (-1)");

        // S-type: sw x3, 40(x2) -> imm[11:5]=7'b0000001, imm[4:0]=5'b01000 (0x28)
        // {7'b0000001, 5'd3, 5'd2, 3'b010, 5'b01000, 7'b0100011} = 0x02312423
        check_imm(32'h0231_2423, 2'b01, 32'h0000_0028, "S-type Positive (0x28)");

        // S-type: sw x3, -1(x2) -> imm = -1 (0xFFFFFFFF)
        // {7'b1111111, 5'd3, 5'd2, 3'b010, 5'b11111, 7'b0100011} = 0xFE312FA3
        check_imm(32'hFE31_2FA3, 2'b01, 32'hFFFF_FFFF, "S-type Negative (-1)");

        // B-type: beq x1, x2, +8 -> offset = +8
        // imm[12]=0, imm[10:5]=0, imm[4:1]=4, imm[11]=0
        // {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b0100, 1'b0, 7'b1100011} = 0x00208463
        check_imm(32'h0020_8463, 2'b10, 32'h0000_0008, "B-type Positive (+8 bytes)");

        // J-type: jal x1, +8 -> offset = +8
        // imm[20]=0, imm[10:1]=4, imm[11]=0, imm[19:12]=0
        // {1'b0, 10'b0000000100, 1'b0, 8'b00000000, 5'd1, 7'b1101111} = 0x008000EF
        check_imm(32'h0080_00EF, 2'b11, 32'h0000_0008, "J-type Positive (+8 bytes)");

        if (errors == 0) begin
            $display("[TB] Test Result: PASSED! (0 errors across all immediate formats)");
        end else begin
            $display("[TB] Test Result: FAILED with %0d errors!", errors);
        end
        $finish;
    end

endmodule
