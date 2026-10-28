// =============================================================================
// Module: trap_unit
// Purpose: Handles Exception & Interrupt Arbitration, Cause Encoding,
//          and Vectored PC Address Calculation.
// Reference: CORE-V-WALLY (1tops_soc) src/privileged/trap.sv & csr.sv
// =============================================================================

module trap_unit #(parameter WIDTH = 32) (
    // Exception inputs from Memory stage
    input              IllegalInstrM,    // Illegal instruction detected
    input              BreakpointFaultM, // ebreak in M stage
    input              EcallFaultM,      // ecall in M stage
    input              InstrMisalignedM, // Misaligned instruction fetch
    input  [WIDTH-1:0] PCM,              // PC of instruction in M stage
    input  [WIDTH-1:0] InstrM,           // Instruction word in M stage
    // Machine status & configuration registers from csr_file
    input  [WIDTH-1:0] mstatus,          // Bit 3 = MIE
    input  [WIDTH-1:0] mie,              // Bit 11=MEIE, 7=MTIE, 3=MSIE
    input  [WIDTH-1:0] mip,              // Bit 11=MEIP, 7=MTIP, 3=MSIP
    input  [WIDTH-1:0] mtvec,            // Trap vector base register
    // Outputs to Datapath, CSR File, and Hazard Unit
    output             TrapM,            // 1 when any trap is taken
    output             InterruptM,       // 1 if trap is an interrupt, 0 if exception
    output             IntPendingM,      // 1 if any unmasked interrupt is pending
    output [WIDTH-1:0] TrapCauseM,       // Value written into mcause
    output [WIDTH-1:0] TrapValM,         // Value written into mtval
    output [WIDTH-1:0] TrapVectorM       // Next PC address to jump to
);

    // 1. Pending & Enabled Interrupts
    wire [11:0] PendingInts = mip[11:0] & mie[11:0];
    assign IntPendingM      = |PendingInts;
    wire MIntGlobalEn       = mstatus[3]; // mstatus.MIE

    // Valid interrupt occurs if global MIE is set and an unmasked interrupt is pending
    assign InterruptM       = MIntGlobalEn & IntPendingM;

    // 2. Exception detection
    wire ExceptionM = IllegalInstrM | BreakpointFaultM | EcallFaultM | InstrMisalignedM;

    // Trap is the union of interrupts and exceptions
    assign TrapM = InterruptM | ExceptionM;

    // 3. Priority Arbitration & Cause Encoding (RISC-V Privileged Spec 3.1.15)
    reg [4:0]       CauseCode;
    reg [WIDTH-1:0] TrapVal_int;

    always @(*) begin
        if (InterruptM) begin
            // Interrupt priorities: MEI (11) > MSI (3) > MTI (7)
            if      (PendingInts[11]) CauseCode = 5'd11; // Machine External Interrupt
            else if (PendingInts[3])  CauseCode = 5'd3;  // Machine Software Interrupt
            else if (PendingInts[7])  CauseCode = 5'd7;  // Machine Timer Interrupt
            else                      CauseCode = 5'd0;
            TrapVal_int = 32'd0;
        end else begin
            // Exception priorities: Misaligned (0) > Illegal (2) > Breakpoint (3) > Ecall (11)
            if (InstrMisalignedM) begin
                CauseCode   = 5'd0;
                TrapVal_int = PCM;
            end else if (IllegalInstrM) begin
                CauseCode   = 5'd2;
                TrapVal_int = InstrM;
            end else if (BreakpointFaultM) begin
                CauseCode   = 5'd3;
                TrapVal_int = PCM;
            end else if (EcallFaultM) begin
                CauseCode   = 5'd11;
                TrapVal_int = 32'd0;
            end else begin
                CauseCode   = 5'd0;
                TrapVal_int = 32'd0;
            end
        end
    end

    // mcause: bit 31 = Interrupt flag, bits [4:0] = Exception/Interrupt cause code
    assign TrapCauseM = {InterruptM, 26'b0, CauseCode};
    assign TrapValM   = TrapVal_int;

    // 4. Trap Vectoring (Direct vs Vectored Mode)
    // mtvec[1:0] == 2'b00 : Direct mode   (all traps jump to mtvec[31:2] << 2)
    // mtvec[1:0] == 2'b01 : Vectored mode (exceptions to base, interrupts to base + 4 * Cause)
    wire [WIDTH-1:0] BaseVec = {mtvec[WIDTH-1:2], 2'b00};
    wire Vectored = InterruptM & (mtvec[1:0] == 2'b01);
    wire [WIDTH-1:0] VectoredVec = BaseVec + {25'b0, CauseCode, 2'b00};

    assign TrapVectorM = Vectored ? VectoredVec : BaseVec;

endmodule
