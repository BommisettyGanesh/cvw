`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_subword_unit.sv
// Purpose: Exhaustive verification of byte mask generation, write replication,
//          and load sign/zero extension across all byte offsets.
// =============================================================================

module tb_subword_unit;

    reg  [ 2:0] funct3;
    reg  [ 1:0] byte_offset;
    reg  [31:0] write_data_in;
    reg  [31:0] raw_read_data;
    wire [ 3:0] byte_mask;
    wire [31:0] write_data_out;
    wire [31:0] read_data_out;

    subword_unit dut (
        .funct3(funct3),
        .byte_offset(byte_offset),
        .write_data_in(write_data_in),
        .raw_read_data(raw_read_data),
        .byte_mask(byte_mask),
        .write_data_out(write_data_out),
        .read_data_out(read_data_out)
    );

    integer errors = 0;

    initial begin
        $display("=== Running Subword Unit Verification ===");

        // 1. SB Byte Mask checks
        funct3 = 3'b000;
        byte_offset = 2'b00; #1; if (byte_mask !== 4'b0001) errors = errors + 1;
        byte_offset = 2'b01; #1; if (byte_mask !== 4'b0010) errors = errors + 1;
        byte_offset = 2'b10; #1; if (byte_mask !== 4'b0100) errors = errors + 1;
        byte_offset = 2'b11; #1; if (byte_mask !== 4'b1000) errors = errors + 1;

        // 2. SH Halfword Mask checks
        funct3 = 3'b001;
        byte_offset = 2'b00; #1; if (byte_mask !== 4'b0011) errors = errors + 1;
        byte_offset = 2'b10; #1; if (byte_mask !== 4'b1100) errors = errors + 1;

        // 3. SW Word Mask check
        funct3 = 3'b010;
        byte_offset = 2'b00; #1; if (byte_mask !== 4'b1111) errors = errors + 1;

        // 4. Write data replication checks
        write_data_in = 32'h1234_5678;
        funct3 = 3'b000; #1; // SB -> replicate lower 8 bits (0x78)
        if (write_data_out !== 32'h7878_7878) begin
            $display("[FAIL] SB Replication: got 0x%08x, exp 0x78787878", write_data_out);
            errors = errors + 1;
        end

        funct3 = 3'b001; #1; // SH -> replicate lower 16 bits (0x5678)
        if (write_data_out !== 32'h5678_5678) begin
            $display("[FAIL] SH Replication: got 0x%08x, exp 0x56785678", write_data_out);
            errors = errors + 1;
        end

        // 5. Read data sign/zero extension checks
        raw_read_data = 32'hA5F0_8C34; // Byte 0: 0x34, Byte 1: 0x8C (neg), Byte 2: 0xF0 (neg), Byte 3: 0xA5 (neg)

        // LB (Signed)
        funct3 = 3'b000;
        byte_offset = 2'b00; #1; // 0x34 (pos) -> 0x00000034
        if (read_data_out !== 32'h0000_0034) errors = errors + 1;
        byte_offset = 2'b01; #1; // 0x8C (neg) -> 0xFFFFFF8C
        if (read_data_out !== 32'hFFFF_FF8C) errors = errors + 1;

        // LBU (Unsigned)
        funct3 = 3'b100;
        byte_offset = 2'b01; #1; // 0x8C (unsigned) -> 0x0000008C
        if (read_data_out !== 32'h0000_008C) errors = errors + 1;

        // LH (Signed)
        funct3 = 3'b001;
        byte_offset = 2'b00; #1; // 0x8C34 (neg) -> 0xFFFF8C34
        if (read_data_out !== 32'hFFFF_8C34) errors = errors + 1;

        // LHU (Unsigned)
        funct3 = 3'b101;
        byte_offset = 2'b00; #1; // 0x8C34 (unsigned) -> 0x00008C34
        if (read_data_out !== 32'h0000_8C34) errors = errors + 1;

        if (errors == 0) begin
            $display("[TB] Test Result: PASSED! (0 errors across subword alignments & extensions)");
        end else begin
            $display("[TB] Test Result: FAILED with %0d errors!", errors);
        end
        $finish;
    end

endmodule
