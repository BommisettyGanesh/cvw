// uart_apb.sv
// Purpose: APB Interface to 16550-compatible UART with Simulation Console Stream

module uart_apb #(
    parameter XLEN          = 32,
    parameter UART_PRESCALE = 1,
    parameter USE_REAL_UART = 0
)(
    input  logic              PCLK,
    input  logic              PRESETn,
    input  logic              PSEL,
    input  logic [ 2:0]       PADDR,
    input  logic [XLEN-1:0]   PWDATA,
    input  logic [XLEN/8-1:0] PSTRB,
    input  logic              PWRITE,
    input  logic              PENABLE,
    output logic [XLEN-1:0]   PRDATA,
    output logic              PREADY,
    input  logic              SIN,
    output logic              SOUT,
    output logic              INTR,

    // Optional Modem & Flow Control Pins (Compatible with Wally RS232 E1A driver)
    input  logic              DSRb,
    input  logic              DCDb,
    input  logic              CTSb,
    input  logic              RIb,
    output logic              RTSb,
    output logic              DTRb,
    output logic              OUT1b,
    output logic              OUT2b,
    output logic              TXRDYb,
    output logic              RXRDYb
);

generate
if (USE_REAL_UART == 1) begin : gen_real_uart
    // Full bit-by-bit TI PC16550D hardware UART with baud generator & FIFOs
    logic [2:0] entry;
    logic       MEMRb, MEMWb, memread, memwrite;
    logic [7:0] Din, Dout;
    logic       BAUDOUTb;

    assign memwrite = PWRITE & PENABLE & PSEL;
    assign memread  = ~PWRITE & PENABLE & PSEL;
    assign PREADY   = 1'b1;
    assign entry    = PADDR[2:0];
    assign MEMRb    = ~memread;
    assign MEMWb    = ~memwrite;
    assign Din      = PWDATA[7:0];

    if (XLEN == 64) assign PRDATA = {8{Dout}};
    else            assign PRDATA = {4{Dout}};

    uartPC16550D #(UART_PRESCALE) uartPC (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .A(entry),
        .Din(Din),
        .Dout(Dout),
        .MEMRb(MEMRb),
        .MEMWb(MEMWb),
        .INTR(INTR),
        .TXRDYb(TXRDYb),
        .RXRDYb(RXRDYb),
        .BAUDOUTb(BAUDOUTb),
        .RCLK(BAUDOUTb),
        .SIN(SIN),
        .DSRb(DSRb),
        .DCDb(DCDb),
        .CTSb(CTSb),
        .RIb(RIb),
        .SOUT(SOUT),
        .RTSb(RTSb),
        .DTRb(DTRb),
        .OUT1b(OUT1b),
        .OUT2b(OUT2b)
    );

end else begin : gen_fast_model
    // Fast Zero-Wait-State 16550 Model with Direct Simulation Console Output
    // Matching main/uart_apb.v for high-throughput software and benchmarks
    localparam UART_RBR_THR_DLL = 3'b000;
    localparam UART_IER_DLM     = 3'b001;
    localparam UART_IIR_FCR     = 3'b010;
    localparam UART_LCR         = 3'b011;
    localparam UART_MCR         = 3'b100;
    localparam UART_LSR         = 3'b101;
    localparam UART_MSR         = 3'b110;
    localparam UART_SCR         = 3'b111;

    logic [7:0] dll, dlm;
    logic [7:0] ier;
    logic [7:0] lcr;
    logic [7:0] mcr;
    logic [7:0] scr;

    wire memwrite = PWRITE & PENABLE & PSEL;
    assign PREADY = 1'b1;

    wire [7:0] din = PWDATA[7:0];
    logic [7:0] dout;

    // Line Status Register: THRE (bit 5) = 1, TEMT (bit 6) = 1 (Always Ready to Transmit)
    wire [7:0] lsr = 8'h60;

    // Interrupt line: triggers if transmitter empty interrupt is enabled
    assign INTR = ier[1] & lsr[5];

    assign RTSb   = 1'b0;
    assign DTRb   = 1'b0;
    assign OUT1b  = 1'b1;
    assign OUT2b  = 1'b1;
    assign TXRDYb = 1'b0;
    assign RXRDYb = 1'b1;

    // Read Multiplexer
    always_comb begin
        case (PADDR)
            UART_RBR_THR_DLL: dout = (lcr[7]) ? dll : 8'd0;
            UART_IER_DLM:     dout = (lcr[7]) ? dlm : ier;
            UART_IIR_FCR:     dout = 8'h01; // No interrupt pending
            UART_LCR:         dout = lcr;
            UART_MCR:         dout = mcr;
            UART_LSR:         dout = lsr;
            UART_MSR:         dout = 8'h00;
            UART_SCR:         dout = scr;
            default:          dout = 8'd0;
        endcase
    end

    // Replicate byte across all byte lanes of PRDATA
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA <= '0;
        end else begin
            if (XLEN == 64) PRDATA <= {8{dout}};
            else            PRDATA <= {4{dout}};
        end
    end

    // Write Registers & Simulation Console Output
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            dll  <= 8'd0;
            dlm  <= 8'd0;
            ier  <= 8'd0;
            lcr  <= 8'h03; // 8-bit word length
            mcr  <= 8'd0;
            scr  <= 8'd0;
            SOUT <= 1'b1;
        end else if (memwrite) begin
            case (PADDR)
                UART_RBR_THR_DLL: begin
                    if (lcr[7]) begin
                        dll <= din;
                    end else begin
                        SOUT <= din[0];
`ifndef SYNTHESIS
                        // synthesis translate_off
                        $write("%c", din);
                        $fflush();
                        // synthesis translate_on
`endif
                    end
                end
                UART_IER_DLM: begin
                    if (lcr[7]) dlm <= din;
                    else        ier <= din;
                end
                UART_LCR: lcr <= din;
                UART_MCR: mcr <= din;
                UART_SCR: scr <= din;
                default: ;
            endcase
        end
    end
end
endgenerate

endmodule
