// gpio_apb.sv
// Purpose: General-Purpose I/O (GPIO) on APB Bus

module gpio_apb #(
    parameter XLEN = 32
)(
    input  logic              PCLK,
    input  logic              PRESETn,
    input  logic              PSEL,
    input  logic [ 7:0]       PADDR,
    input  logic [31:0]       PWDATA,
    input  logic [ 3:0]       PSTRB,
    input  logic              PWRITE,
    input  logic              PENABLE,
    output logic [31:0]       PRDATA,
    output logic              PREADY,
    input  logic [31:0]       GPIOIN,
    output logic [31:0]       GPIOOUT,
    output logic [31:0]       GPIOEN,
    output logic              GPIOIntr
);

    localparam GPIO_INPUT_VAL  = 8'h00;
    localparam GPIO_INPUT_EN   = 8'h04;
    localparam GPIO_OUTPUT_EN  = 8'h08;
    localparam GPIO_OUTPUT_VAL = 8'h0C;
    localparam GPIO_RISE_IE    = 8'h18;
    localparam GPIO_RISE_IP    = 8'h1C;
    localparam GPIO_FALL_IE    = 8'h20;
    localparam GPIO_FALL_IP    = 8'h24;
    localparam GPIO_HIGH_IE    = 8'h28;
    localparam GPIO_HIGH_IP    = 8'h2C;
    localparam GPIO_LOW_IE     = 8'h30;
    localparam GPIO_LOW_IP     = 8'h34;

    logic [31:0] input_en;
    logic [31:0] rise_ie, rise_ip;
    logic [31:0] fall_ie, fall_ip;
    logic [31:0] high_ie, high_ip;
    logic [31:0] low_ie,  low_ip;

    logic [31:0] gpioin_d;

    wire memwrite = PWRITE & PENABLE & PSEL;
    assign PREADY = 1'b1;

    wire [31:0] ip = (rise_ip & rise_ie) | (fall_ip & fall_ie) |
                     (high_ip & high_ie) | (low_ip  & low_ie);
    assign GPIOIntr = |ip;

    // Synchronize GPIO inputs and edge detect
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpioin_d <= 32'd0;
        end else begin
            gpioin_d <= GPIOIN & input_en;
        end
    end

    // APB Read
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA <= 32'd0;
        end else begin
            case (PADDR)
                GPIO_INPUT_VAL:  PRDATA <= GPIOIN & input_en;
                GPIO_INPUT_EN:   PRDATA <= input_en;
                GPIO_OUTPUT_EN:  PRDATA <= GPIOEN;
                GPIO_OUTPUT_VAL: PRDATA <= GPIOOUT;
                GPIO_RISE_IE:    PRDATA <= rise_ie;
                GPIO_RISE_IP:    PRDATA <= rise_ip;
                GPIO_FALL_IE:    PRDATA <= fall_ie;
                GPIO_FALL_IP:    PRDATA <= fall_ip;
                GPIO_HIGH_IE:    PRDATA <= high_ie;
                GPIO_HIGH_IP:    PRDATA <= high_ip;
                GPIO_LOW_IE:     PRDATA <= low_ie;
                GPIO_LOW_IP:     PRDATA <= low_ip;
                default:         PRDATA <= 32'd0;
            endcase
        end
    end

    // APB Write
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            input_en <= 32'd0;
            GPIOEN   <= 32'd0;
            GPIOOUT  <= 32'd0;
            rise_ie  <= 32'd0;
            rise_ip  <= 32'd0;
            fall_ie  <= 32'd0;
            fall_ip  <= 32'd0;
            high_ie  <= 32'd0;
            high_ip  <= 32'd0;
            low_ie   <= 32'd0;
            low_ip   <= 32'd0;
        end else if (memwrite) begin
            case (PADDR)
                GPIO_INPUT_EN:   input_en <= PWDATA;
                GPIO_OUTPUT_EN:  GPIOEN   <= PWDATA;
                GPIO_OUTPUT_VAL: GPIOOUT  <= PWDATA;
                GPIO_RISE_IE:    rise_ie  <= PWDATA;
                GPIO_RISE_IP:    rise_ip  <= rise_ip & ~PWDATA; // W1C
                GPIO_FALL_IE:    fall_ie  <= PWDATA;
                GPIO_FALL_IP:    fall_ip  <= fall_ip & ~PWDATA;
                GPIO_HIGH_IE:    high_ie  <= PWDATA;
                GPIO_HIGH_IP:    high_ip  <= high_ip & ~PWDATA;
                GPIO_LOW_IE:     low_ie   <= PWDATA;
                GPIO_LOW_IP:     low_ip   <= low_ip & ~PWDATA;
                default: ;
            endcase
        end else begin
            // Track edges
            rise_ip <= rise_ip | ((GPIOIN & input_en) & ~gpioin_d);
            fall_ip <= fall_ip | (~(GPIOIN & input_en) & gpioin_d);
            high_ip <= (GPIOIN & input_en);
            low_ip  <= (~(GPIOIN & input_en));
        end
    end

endmodule
