// ahbapbbridge.sv
// Purpose: AMBA 3 AHB-Lite to APB 3 Bridge

module ahbapbbridge #(
    parameter XLEN    = 32,
    parameter PERIPHS = 4
)(
    input  logic                      HCLK,
    input  logic                      HRESETn,
    input  logic [PERIPHS-1:0]        HSEL,
    input  logic [31:0]               HADDR,
    input  logic [XLEN-1:0]           HWDATA,
    input  logic [XLEN/8-1:0]         HWSTRB,
    input  logic                      HWRITE,
    input  logic [ 1:0]               HTRANS,
    input  logic                      HREADY,
    output logic [XLEN-1:0]           HRDATA,
    output logic                      HRESP,
    output logic                      HREADYOUT,

    // APB Master Bus
    output logic                      PCLK,
    output logic                      PRESETn,
    output logic [PERIPHS-1:0]        PSEL,
    output logic                      PWRITE,
    output logic                      PENABLE,
    output logic [31:0]               PADDR,
    output logic [XLEN-1:0]           PWDATA,
    output logic [XLEN/8-1:0]         PSTRB,
    input  logic [PERIPHS-1:0]        PREADY,
    input  logic [PERIPHS*XLEN-1:0]   PRDATA
);

    assign PCLK    = HCLK;
    assign PRESETn = HRESETn;

    logic initTrans;
    logic initTransSel;
    logic initTransSelD;
    logic PREADYOUT;

    assign initTrans    = HTRANS[1] & HREADY;
    assign initTransSel = initTrans & (|HSEL);

    // Delay AHB Address phase signals to align with APB setup phase
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            PADDR         <= 32'd0;
            PWRITE        <= 1'b0;
            PSEL          <= '0;
            initTransSelD <= 1'b0;
            PENABLE       <= 1'b0;
        end else begin
            if (HREADY) begin
                PADDR  <= HADDR;
                PWRITE <= HWRITE;
                PSEL   <= HSEL & {PERIPHS{initTrans}};
            end
            initTransSelD <= initTransSel;
            PENABLE       <= PENABLE ? ~HREADY : initTransSelD;
        end
    end

    assign PWDATA = HWDATA;
    assign PSTRB  = HWSTRB;

    // Multiplex read data and ready signals from selected APB peripheral
    always_comb begin
        HRDATA    = '0;
        PREADYOUT = 1'b1;
        for (int i = 0; i < PERIPHS; i++) begin
            if (PSEL[i]) begin
                HRDATA    = PRDATA[i*XLEN +: XLEN];
                PREADYOUT = PREADY[i];
            end
        end
    end

    // Hold HREADYOUT low during setup cycle, release when APB access phase completes
    assign HREADYOUT = PREADYOUT & ~initTransSelD;
    assign HRESP     = 1'b0; // Bridge returns OKAY

endmodule
