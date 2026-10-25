// =============================================================================
// Module: ahbinterface
// Purpose: AMBA 3 AHB-Lite Client Interface for IFU and LSU
// Reference: cvw/1tops_soc/src/ebu/ahbinterface.sv & busfsm.sv
// =============================================================================

module ahbinterface #(
    parameter IS_LSU = 1'b1  // 1: LSU (Read/Write with HWDATA), 0: IFU (Read-Only)
)(
    input             HCLK,
    input             HRESETn,
    input             Flush,        // Pipeline stage flush
    input             Stall,        // Pipeline stage stall

    // Core / Pipeline Interface
    input             Req,          // Request transfer
    input             Write,        // 1 = Write, 0 = Read
    input      [31:0] Addr,         // Address
    input      [ 2:0] Size,         // 000=Byte, 001=Half, 010=Word
    input      [ 3:0] ByteMask,     // Byte enables
    input      [31:0] WriteData,    // Write data from core
    output     [31:0] FetchBuffer,  // Latched read data from bus
    output            BusStall,     // Stalls pipeline while bus is busy
    output     [31:0] Addr_DataPhase, // Address corresponding to active Data Phase
    output            DataPhase,    // 1 when in Data Phase

    // AHB-Lite Interface to EBU / Arbiter
    output     [ 1:0] HTRANS,       // 00=IDLE, 10=NONSEQ
    output            HWRITE,       // 1=Write, 0=Read
    output     [31:0] HADDR,        // Address to bus
    output     [ 2:0] HSIZE,        // Transfer size
    output reg [31:0] HWDATA,       // Data phase write data
    output reg [ 3:0] HWSTRB,       // Data phase byte strobe
    input      [31:0] HRDATA,       // Read data from bus
    input             HREADY        // Transfer complete handshake
);

    localparam STATE_IDLE = 1'b0;
    localparam STATE_DATA = 1'b1;

    reg state, next_state;

    // Registers to delay write data and strobe by 1 clock cycle (Address -> Data phase)
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HWDATA <= 32'd0;
            HWSTRB <= 4'd0;
        end else if (HREADY) begin
            HWDATA <= WriteData;
            HWSTRB <= ByteMask;
        end
    end

    reg [31:0] live_addr_data_phase;
    reg [31:0] fetch_buf;
    reg [31:0] addr_buf;
    reg        fetch_buf_valid;

    // Latched address corresponding to the current Data Phase
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            live_addr_data_phase <= 32'd0;
        else if (HREADY && HTRANS[1])
            live_addr_data_phase <= Addr;
    end

    assign Addr_DataPhase = (!IS_LSU && fetch_buf_valid) ? addr_buf : live_addr_data_phase;
    assign DataPhase = (state == STATE_DATA && HREADY) || (!IS_LSU && fetch_buf_valid);

    // Bus FSM: Address Phase -> Data Phase
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            state <= STATE_IDLE;
        else if (Flush)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    // Next state logic
    always @(*) begin
        case (state)
            STATE_IDLE: begin
                if (Req && !Stall && HREADY)
                    next_state = STATE_DATA;
                else
                    next_state = STATE_IDLE;
            end
            STATE_DATA: begin
                if (HREADY) begin
                    if (!IS_LSU && Req && !Stall)
                        next_state = STATE_DATA; // Pipelined continuous transfer for IFU
                    else
                        next_state = STATE_IDLE; // Transfer finished, return to IDLE
                end else begin
                    next_state = STATE_DATA;     // Wait-state hold
                end
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    // AHB Address Phase Outputs
    assign HTRANS = (Req && !Stall && (state == STATE_IDLE || (!IS_LSU && HREADY))) ? 2'b10 : 2'b00; // 2'b10 = NONSEQ
    assign HWRITE = (IS_LSU) ? Write : 1'b0;
    assign HADDR  = Addr;
    assign HSIZE  = Size;

    // Fetch buffer management: captures data when stalled and releases when unfreezing
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            fetch_buf       <= 32'd0;
            addr_buf        <= 32'd0;
            fetch_buf_valid <= 1'b0;
        end else if (Flush) begin
            fetch_buf       <= 32'd0;
            addr_buf        <= 32'd0;
            fetch_buf_valid <= 1'b0;
        end else if (!IS_LSU) begin
            if (state == STATE_DATA && HREADY) begin
                if (Stall) begin
                    fetch_buf       <= HRDATA;
                    addr_buf        <= live_addr_data_phase;
                    fetch_buf_valid <= 1'b1;
                end else if (fetch_buf_valid) begin
                    fetch_buf_valid <= 1'b0;
                end
            end else if (!Stall && fetch_buf_valid) begin
                fetch_buf_valid <= 1'b0;
            end
        end else begin
            // LSU
            if (state == STATE_DATA && HREADY && !HWRITE)
                fetch_buf <= HRDATA;
        end
    end

    // Output live HRDATA during Data Phase if HREADY and not buffered, otherwise buffered data
    assign FetchBuffer = (!IS_LSU && fetch_buf_valid) ? fetch_buf :
                         (state == STATE_DATA && HREADY) ? HRDATA : fetch_buf;

    // Bus Stall: Pipeline must stall while waiting for Address -> Data Phase completion
    assign BusStall = (IS_LSU) ? ((Req && state == STATE_IDLE) || (state == STATE_DATA && !HREADY))
                               : (!HREADY);

endmodule
