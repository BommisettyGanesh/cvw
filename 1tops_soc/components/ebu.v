// =============================================================================
// Module: ebu
// Purpose: External Bus Unit - Arbitrates IFU and LSU onto single AHB-Lite bus
// Reference: cvw/1tops_soc/src/ebu/ebu.sv, controllerinput.sv, ebufsmarb.sv
// =============================================================================

module ebu (
    input             HCLK,
    input             HRESETn,

    // Interface from IFU (Instruction Fetch)
    input      [31:0] IFUHADDR,
    input      [ 1:0] IFUHTRANS,
    input      [ 2:0] IFUHSIZE,
    output            IFUHREADY,

    // Interface from LSU (Data Load/Store)
    input      [31:0] LSUHADDR,
    input      [ 1:0] LSUHTRANS,
    input             LSUHWRITE,
    input      [ 2:0] LSUHSIZE,
    input      [31:0] LSUHWDATA,
    input      [ 3:0] LSUHWSTRB,
    output            LSUHREADY,

    // Unified AHB-Lite Master Bus Output
    output     [31:0] HADDR,
    output     [31:0] HWDATA,
    output     [ 3:0] HWSTRB,
    output            HWRITE,
    output     [ 2:0] HSIZE,
    output     [ 2:0] HBURST,
    output     [ 3:0] HPROT,
    output     [ 1:0] HTRANS,
    output            HMASTLOCK,
    input      [31:0] HRDATA,
    input             HREADY,
    input             HRESP
);

    wire LSUReq = (LSUHTRANS != 2'b00);
    wire IFUReq = (IFUHTRANS != 2'b00);

    // Save/Restore buffer for IFU when preempted by LSU
    reg [31:0] IFUHADDR_saved;
    reg [ 2:0] IFUHSIZE_saved;
    reg        IFU_saved_valid;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            IFUHADDR_saved  <= 32'd0;
            IFUHSIZE_saved  <= 3'd0;
            IFU_saved_valid <= 1'b0;
        end else if (LSUReq && IFUReq && !IFU_saved_valid) begin
            // Preemption: Save IFU request while LSU takes priority
            IFUHADDR_saved  <= IFUHADDR;
            IFUHSIZE_saved  <= IFUHSIZE;
            IFU_saved_valid <= 1'b1;
        end else if (IFU_saved_valid && HREADY && !LSUReq) begin
            // Restored and completed
            IFU_saved_valid <= 1'b0;
        end
    end

    // Arbitration: LSU has strict priority over IFU
    wire LSUSelect = LSUReq;
    wire IFUSelect = ~LSUReq && (IFUReq || IFU_saved_valid);

    // Multiplexed Address Phase Signals
    assign HADDR  = LSUSelect ? LSUHADDR  : (IFU_saved_valid ? IFUHADDR_saved : IFUHADDR);
    assign HTRANS = LSUSelect ? LSUHTRANS : (IFU_saved_valid ? 2'b10           : IFUHTRANS);
    assign HSIZE  = LSUSelect ? LSUHSIZE  : (IFU_saved_valid ? IFUHSIZE_saved : IFUHSIZE);
    assign HWRITE = LSUSelect ? LSUHWRITE : 1'b0;
    assign HBURST = 3'b000;              // Single transfer (no burst)
    assign HPROT  = {3'b001, LSUSelect}; // User/Privileged Opcode or Data access
    assign HMASTLOCK = 1'b0;

    // Multiplexed Data Phase Signals (only LSU writes data)
    assign HWDATA = LSUHWDATA;
    assign HWSTRB = LSUHWSTRB;

    // Track active client in Data Phase
    reg lsu_data_phase;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            lsu_data_phase <= 1'b0;
        else if (HREADY)
            lsu_data_phase <= LSUSelect;
    end

    // Ready handshake demultiplexing
    assign LSUHREADY = HREADY & (LSUSelect | lsu_data_phase);
    assign IFUHREADY = HREADY & ~lsu_data_phase;

endmodule
