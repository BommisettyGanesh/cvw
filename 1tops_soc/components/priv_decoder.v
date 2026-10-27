// =============================================================================
// Module: priv_decoder
// Purpose: Decodes RISC-V Privileged Instructions (M-Mode)
// Reference: CORE-V-WALLY (1tops_soc) src/privileged/privdec.sv
// =============================================================================

module priv_decoder (
    input  [31:0] InstrD,
    output        PrivilegedD,   // 1 if SYSTEM opcode (0x73) with funct3 == 000
    output        CSRInstrD,     // 1 if SYSTEM opcode (0x73) with funct3 != 000
    output        mretD,         // Machine return from trap
    output        wfiD,          // Wait for interrupt
    output        ecallD,        // Environment call
    output        ebreakD,       // Breakpoint
    output        IllegalPrivD,  // Illegal privileged instruction
    output        IllegalCSRD    // Illegal CSR access (funct3 == 100)
);

    wire [6:0]  op     = InstrD[6:0];
    wire [2:0]  funct3 = InstrD[14:12];
    wire [11:0] funct12= InstrD[31:20];
    wire [4:0]  rs1    = InstrD[19:15];
    wire [4:0]  rd     = InstrD[11:7];

    wire is_system = (op == 7'b1110011);

    // Privileged instructions have funct3 == 3'b000
    assign PrivilegedD = is_system && (funct3 == 3'b000);
    // CSR instructions have funct3 != 3'b000 (and != 3'b100)
    assign CSRInstrD   = is_system && (funct3 != 3'b000) && (funct3 != 3'b100);

    // Specific privileged instruction decoding
    // Standard RISC-V requires rs1 == 0 and rd == 0 for these instructions
    assign mretD   = PrivilegedD && (funct12 == 12'h302) && (rs1 == 5'b00000) && (rd == 5'b00000);
    assign wfiD    = PrivilegedD && (funct12 == 12'h105) && (rs1 == 5'b00000) && (rd == 5'b00000);
    assign ecallD  = PrivilegedD && (funct12 == 12'h000) && (rs1 == 5'b00000) && (rd == 5'b00000);
    assign ebreakD = PrivilegedD && (funct12 == 12'h001) && (rs1 == 5'b00000) && (rd == 5'b00000);

    // Any other funct12 pattern with funct3 == 3'b000 is an illegal privileged instruction
    assign IllegalPrivD = PrivilegedD && !(mretD | wfiD | ecallD | ebreakD);

    // funct3 == 3'b100 is reserved in SYSTEM space
    assign IllegalCSRD  = is_system && (funct3 == 3'b100);

endmodule
