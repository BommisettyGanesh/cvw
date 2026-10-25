// =============================================================================
// Module: subword_unit
// Purpose: Subword Load and Store Processing Unit for RISC-V RV32I Datapath
//          - Subword store byte strobe generation (SB, SH, SW)
//          - Subword store write data replication across byte lanes
//          - Subword load data selection and sign/zero extension (LB, LH, LW, LBU, LHU)
// Reference: cvw/1tops_soc/src/lsu/subwordread.sv & subwordwrite.sv & swbytemask.sv
// =============================================================================

module subword_unit (
    input      [ 2:0] funct3,         // Instruction funct3 (specifies size and signedness)
    input      [ 1:0] byte_offset,    // Address lower 2 bits (ALUResultM[1:0])
    input      [31:0] write_data_in,  // Core register write data (WriteDataM)
    input      [31:0] raw_read_data,  // Raw 32-bit word from memory / bus (LSU_RawReadData)
    output reg [ 3:0] byte_mask,      // AHB HWSTRB byte enables (LSUHWSTRB_gen)
    output     [31:0] write_data_out, // Replicated write data for AHB bus (LSUWriteDataM)
    output reg [31:0] read_data_out   // Aligned, sign/zero-extended read data (ReadDataM)
);

    // =========================================================================
    // 1. Subword Store: Byte Mask (HWSTRB) Generation
    // =========================================================================
    always @(*) begin
        case (funct3[1:0])
            2'b00:   byte_mask = 4'b0001 << byte_offset;            // SB: Store Byte
            2'b01:   byte_mask = byte_offset[1] ? 4'b1100 : 4'b0011;// SH: Store Halfword
            default: byte_mask = 4'b1111;                            // SW: Store Word
        endcase
    end

    // =========================================================================
    // 2. Subword Store: Write Data Replication Across Byte Lanes
    // =========================================================================
    assign write_data_out = (funct3[1:0] == 2'b00) ? {4{write_data_in[7:0]}} :
                            (funct3[1:0] == 2'b01) ? {2{write_data_in[15:0]}} :
                            write_data_in;

    // =========================================================================
    // 3. Subword Load: Data Extraction and Sign/Zero Extension
    // =========================================================================
    always @(*) begin
        case (funct3)
            3'b000: begin // LB: Signed Byte
                case (byte_offset)
                    2'b00: read_data_out = {{24{raw_read_data[ 7]}}, raw_read_data[ 7: 0]};
                    2'b01: read_data_out = {{24{raw_read_data[15]}}, raw_read_data[15: 8]};
                    2'b10: read_data_out = {{24{raw_read_data[23]}}, raw_read_data[23:16]};
                    2'b11: read_data_out = {{24{raw_read_data[31]}}, raw_read_data[31:24]};
                endcase
            end
            3'b001: begin // LH: Signed Halfword
                case (byte_offset[1])
                    1'b0:  read_data_out = {{16{raw_read_data[15]}}, raw_read_data[15: 0]};
                    1'b1:  read_data_out = {{16{raw_read_data[31]}}, raw_read_data[31:16]};
                endcase
            end
            3'b100: begin // LBU: Unsigned Byte
                case (byte_offset)
                    2'b00: read_data_out = {24'b0, raw_read_data[ 7: 0]};
                    2'b01: read_data_out = {24'b0, raw_read_data[15: 8]};
                    2'b10: read_data_out = {24'b0, raw_read_data[23:16]};
                    2'b11: read_data_out = {24'b0, raw_read_data[31:24]};
                endcase
            end
            3'b101: begin // LHU: Unsigned Halfword
                case (byte_offset[1])
                    1'b0:  read_data_out = {16'b0, raw_read_data[15: 0]};
                    1'b1:  read_data_out = {16'b0, raw_read_data[31:16]};
                endcase
            end
            default: read_data_out = raw_read_data; // LW: Word (Load Word)
        endcase
    end

endmodule
