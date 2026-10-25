// =============================================================================
// Module: csr_file
// Purpose: RISC-V Machine Mode Control and Status Registers (Zicsr + Zicntr + Privileged)
// Reference: CORE-V-WALLY (1tops_soc) src/privileged/csr.sv, csrm.sv, csri.sv, csrc.sv
// =============================================================================

module csr_file #(parameter WIDTH = 32) (
    input                     clk,
    input                     reset,
    // Access port in Memory (M) stage
    input  [11:0]             CSRAdrM,       // 12-bit CSR address from InstrM[31:20]
    input  [2:0]              Funct3M,       // funct3 field from InstrM[14:12]
    input  [WIDTH-1:0]        SrcAM,         // Forwarded register operand rs1
    input  [4:0]              uimmM,         // 5-bit immediate from InstrM[19:15]
    input  [WIDTH-1:0]        PCM,           // Program counter in Memory stage
    input                     CSRReadM,      // Active when reading CSR
    input                     CSRWriteM,     // Qualified write enable from controller
    output reg [WIDTH-1:0]    CSRReadValM,   // Old CSR value read out
    // Hardware Interrupt Lines
    input                     MTimerInt,     // Machine timer interrupt (CLINT)
    input                     MSwInt,        // Machine software interrupt (CLINT)
    input                     MExtInt,       // Machine external interrupt (PLIC)
    input  [63:0]             MTIME_CLINT,   // Real-time counter from CLINT
    input                     TrapM,         // Asserted when a trap is taken
    input  [WIDTH-1:0]        TrapCauseM,    // Value to record into mcause
    input  [WIDTH-1:0]        TrapValM,      // Value to record into mtval
    input                     mretM,         // Asserted on mret instruction
    input                     ValidM,        // 1 if non-bubble instruction in Memory stage
    // Exported Register Values
    output reg [WIDTH-1:0]    mstatus,
    output reg [WIDTH-1:0]    mie,
    output     [WIDTH-1:0]    mip,
    output reg [WIDTH-1:0]    mtvec,
    output reg [WIDTH-1:0]    mepc
);

    // =========================================================================
    // CSR Register Definitions (M-Mode)
    // =========================================================================
    wire [WIDTH-1:0] misa = 32'h4000_0100;   // 0x301 - RV32I Base ISA
    reg  [WIDTH-1:0] mscratch;               // 0x340 - Scratchpad
    reg  [WIDTH-1:0] mcause;                 // 0x342 - Trap Cause
    reg  [WIDTH-1:0] mtval;                  // 0x343 - Trap Value
    reg  [31:0]      mcounteren;             // 0x306 - Counter Enable
    reg  [31:0]      mcountinhibit;          // 0x320 - Counter Inhibit

    // Read-only Machine Information Registers
    wire [WIDTH-1:0] mvendorid = 32'h0000_0000; // 0xF11 - Non-commercial
    wire [WIDTH-1:0] marchid   = 32'h0000_0000; // 0xF12
    wire [WIDTH-1:0] mimpid    = 32'h0000_0000; // 0xF13
    wire [WIDTH-1:0] mhartid   = 32'h0000_0000; // 0xF14 - Hart 0

    // 64-bit Hardware Performance & Cycle Counters (Zicntr)
    reg [63:0] cycle_cnt;      // 0xC00 (cycle), 0xC80 (cycleh)
    reg [63:0] instret_cnt;    // 0xC02 (instret), 0xC82 (instreth)

    // Hardware Interrupt Pending Register (mip)
    // MEIP (bit 11), MTIP (bit 7), MSIP (bit 3) directly reflect interrupt inputs
    assign mip = {20'b0, MExtInt, 3'b0, MTimerInt, 3'b0, MSwInt, 3'b0};

    // =========================================================================
    // 1. CSR Read Multiplexer (Combinational)
    // =========================================================================
    always @(*) begin
        if (CSRReadM) begin
            case (CSRAdrM)
                // Machine Trap Setup & Handling
                12'h300: CSRReadValM = mstatus;
                12'h301: CSRReadValM = misa;
                12'h304: CSRReadValM = mie;
                12'h305: CSRReadValM = mtvec;
                12'h306: CSRReadValM = mcounteren;
                12'h320: CSRReadValM = mcountinhibit;
                12'h340: CSRReadValM = mscratch;
                12'h341: CSRReadValM = mepc;
                12'h342: CSRReadValM = mcause;
                12'h343: CSRReadValM = mtval;
                12'h344: CSRReadValM = mip;

                // Machine Information
                12'hF11: CSRReadValM = mvendorid;
                12'hF12: CSRReadValM = marchid;
                12'hF13: CSRReadValM = mimpid;
                12'hF14: CSRReadValM = mhartid;

                // User Counters (Zicntr)
                12'hC00: CSRReadValM = cycle_cnt[31:0];
                12'hC80: CSRReadValM = cycle_cnt[63:32];
                12'hC01: CSRReadValM = MTIME_CLINT[31:0];    // time
                12'hC81: CSRReadValM = MTIME_CLINT[63:32];   // timeh
                12'hC02: CSRReadValM = instret_cnt[31:0];
                12'hC82: CSRReadValM = instret_cnt[63:32];

                // Machine Mode Counter Aliases
                12'hB00: CSRReadValM = cycle_cnt[31:0];      // mcycle
                12'hB80: CSRReadValM = cycle_cnt[63:32];     // mcycleh
                12'hB02: CSRReadValM = instret_cnt[31:0];    // minstret
                12'hB82: CSRReadValM = instret_cnt[63:32];   // minstreth

                // HPM Counters (0xC03..0xC1F, 0xC83..0xC9F, 0xB03..0xB1F)
                default: CSRReadValM = 32'h0000_0000;
            endcase
        end else begin
            CSRReadValM = 32'h0000_0000;
        end
    end

    // =========================================================================
    // 2. Wally Next CSR Value Computation
    // =========================================================================
    wire [WIDTH-1:0] CSRSrcM = Funct3M[2] ? { {(WIDTH-5){1'b0}}, uimmM } : SrcAM;

    reg [WIDTH-1:0] CSRWriteValM;
    always @(*) begin
        case (Funct3M[1:0])
            2'b01:   CSRWriteValM = CSRSrcM;                   // CSRRW / CSRRWI
            2'b10:   CSRWriteValM = CSRReadValM | CSRSrcM;     // CSRRS / CSRRSI
            2'b11:   CSRWriteValM = CSRReadValM & ~CSRSrcM;    // CSRRC / CSRRCI
            default: CSRWriteValM = CSRReadValM;
        endcase
    end

    // =========================================================================
    // 3. Sequential CSR Update, Traps, and Counters
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            mstatus       <= 32'h0000_1800; // MPP = 2'b11 (Machine mode on reset)
            mie           <= 32'h0000_0000;
            mtvec         <= 32'h0000_0000;
            mscratch      <= 32'h0000_0000;
            mepc          <= 32'h0000_0000;
            mcause        <= 32'h0000_0000;
            mtval         <= 32'h0000_0000;
            mcounteren    <= 32'h0000_0000;
            mcountinhibit <= 32'h0000_0000;
            cycle_cnt     <= 64'd0;
            instret_cnt   <= 64'd0;
        end else begin
            // 64-bit Cycle Counter (inhibited when mcountinhibit[0] is set)
            if (!mcountinhibit[0])
                cycle_cnt <= cycle_cnt + 64'd1;

            // 64-bit Instructions Retired Counter (inhibited when mcountinhibit[2] is set)
            if (!mcountinhibit[2] && ValidM && !TrapM)
                instret_cnt <= instret_cnt + 64'd1;

            // Trap Entry: hardware trap update takes precedence
            if (TrapM) begin
                mepc          <= {PCM[31:2], 2'b00};        // Save faulting / interrupted PC
                mcause        <= TrapCauseM;                // Save trap cause
                mtval         <= TrapValM;                  // Save trap value
                mstatus[7]    <= mstatus[3];                // MPIE <= MIE
                mstatus[3]    <= 1'b0;                      // MIE <= 0
                mstatus[12:11]<= 2'b11;                     // MPP <= M-mode
            end else if (mretM) begin
                // Trap Return: restore MIE from MPIE
                mstatus[3]    <= mstatus[7];                // MIE <= MPIE
                mstatus[7]    <= 1'b1;                      // MPIE <= 1
                mstatus[12:11]<= 2'b11;                     // MPP <= M-mode
            end else if (CSRWriteM) begin
                // Software CSR Writes
                case (CSRAdrM)
                    12'h300: mstatus  <= (mstatus & ~32'h0000_1888) | (CSRWriteValM & 32'h0000_1888);
                    12'h304: mie      <= CSRWriteValM & 32'h0000_0888; // MEIE, MTIE, MSIE
                    12'h305: mtvec    <= {CSRWriteValM[31:2], CSRWriteValM[1:0]}; // Base + Mode
                    12'h306: mcounteren <= CSRWriteValM;
                    12'h320: mcountinhibit <= CSRWriteValM;
                    12'h340: mscratch <= CSRWriteValM;
                    12'h341: mepc     <= {CSRWriteValM[31:2], 2'b00};  // Word-aligned
                    12'h342: mcause   <= CSRWriteValM;
                    12'h343: mtval    <= CSRWriteValM;
                    12'hC00, 12'hB00: cycle_cnt[31:0]    <= CSRWriteValM;
                    12'hC80, 12'hB80: cycle_cnt[63:32]   <= CSRWriteValM;
                    12'hC02, 12'hB02: instret_cnt[31:0]  <= CSRWriteValM;
                    12'hC82, 12'hB82: instret_cnt[63:32] <= CSRWriteValM;
                    default: ; // Read-only registers ignore writes
                endcase
            end
        end
    end

endmodule
