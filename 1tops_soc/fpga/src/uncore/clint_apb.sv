// clint_apb.sv
// Purpose: Core-Local Interruptor (CLINT) on APB Bus

module clint_apb #(
    parameter XLEN = 32
)(
    input  logic              PCLK,
    input  logic              PRESETn,
    input  logic              PSEL,
    input  logic [15:0]       PADDR,
    input  logic [31:0]       PWDATA,
    input  logic [ 3:0]       PSTRB,
    input  logic              PWRITE,
    input  logic              PENABLE,
    output logic [31:0]       PRDATA,
    output logic              PREADY,
    output logic [63:0]       MTIME,
    output logic              MTimerInt,
    output logic              MSwInt
);

    // Register Offsets (word-aligned)
    localparam CLINT_MSIP      = 16'h0000;
    localparam CLINT_MTIMECMP  = 16'h4000;
    localparam CLINT_MTIMECMPH = 16'h4004;
    localparam CLINT_MTIME     = 16'hBFF8;
    localparam CLINT_MTIMEH    = 16'hBFFC;

    logic        MSIP;
    logic [63:0] MTIMECMP;

    wire [15:0] entry = {PADDR[15:2], 2'b00};
    wire        memwrite = PWRITE & PENABLE & PSEL;

    assign PREADY    = 1'b1; // CLINT responds with zero wait states
    assign MTimerInt = (MTIME >= MTIMECMP);
    assign MSwInt    = MSIP;

    // APB Read
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA <= 32'd0;
        end else begin
            case (entry)
                CLINT_MSIP:      PRDATA <= {31'b0, MSIP};
                CLINT_MTIMECMP:  PRDATA <= MTIMECMP[31:0];
                CLINT_MTIMECMPH: PRDATA <= MTIMECMP[63:32];
                CLINT_MTIME:     PRDATA <= MTIME[31:0];
                CLINT_MTIMEH:    PRDATA <= MTIME[63:32];
                default:         PRDATA <= 32'd0;
            endcase
        end
    end

    // APB Write & Counter Progression
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            MSIP     <= 1'b0;
            MTIMECMP <= 64'hFFFF_FFFF_FFFF_FFFF;
            MTIME    <= 64'd0;
        end else begin
            // MTIME increments every clock cycle unless overwritten
            if (memwrite && (entry == CLINT_MTIME)) begin
                if (PSTRB[0]) MTIME[ 7: 0] <= PWDATA[ 7: 0];
                if (PSTRB[1]) MTIME[15: 8] <= PWDATA[15: 8];
                if (PSTRB[2]) MTIME[23:16] <= PWDATA[23:16];
                if (PSTRB[3]) MTIME[31:24] <= PWDATA[31:24];
            end else if (memwrite && (entry == CLINT_MTIMEH)) begin
                if (PSTRB[0]) MTIME[39:32] <= PWDATA[ 7: 0];
                if (PSTRB[1]) MTIME[47:40] <= PWDATA[15: 8];
                if (PSTRB[2]) MTIME[55:48] <= PWDATA[23:16];
                if (PSTRB[3]) MTIME[63:56] <= PWDATA[31:24];
            end else begin
                MTIME <= MTIME + 64'd1;
            end

            // MSIP write
            if (memwrite && (entry == CLINT_MSIP)) begin
                MSIP <= PWDATA[0];
            end

            // MTIMECMP write
            if (memwrite && (entry == CLINT_MTIMECMP)) begin
                if (PSTRB[0]) MTIMECMP[ 7: 0] <= PWDATA[ 7: 0];
                if (PSTRB[1]) MTIMECMP[15: 8] <= PWDATA[15: 8];
                if (PSTRB[2]) MTIMECMP[23:16] <= PWDATA[23:16];
                if (PSTRB[3]) MTIMECMP[31:24] <= PWDATA[31:24];
            end else if (memwrite && (entry == CLINT_MTIMECMPH)) begin
                if (PSTRB[0]) MTIMECMP[39:32] <= PWDATA[ 7: 0];
                if (PSTRB[1]) MTIMECMP[47:40] <= PWDATA[15: 8];
                if (PSTRB[2]) MTIMECMP[55:48] <= PWDATA[23:16];
                if (PSTRB[3]) MTIMECMP[63:56] <= PWDATA[31:24];
            end
        end
    end

endmodule
