// plic_apb.sv
// Purpose: Platform-Level Interrupt Controller (PLIC) on APB Bus

module plic_apb #(
    parameter XLEN = 32
)(
    input  logic              PCLK,
    input  logic              PRESETn,
    input  logic              PSEL,
    input  logic [27:0]       PADDR,
    input  logic [31:0]       PWDATA,
    input  logic [ 3:0]       PSTRB,
    input  logic              PWRITE,
    input  logic              PENABLE,
    output logic [31:0]       PRDATA,
    output logic              PREADY,
    input  logic              UARTIntr,
    input  logic              GPIOIntr,
    input  logic              SPIIntr,
    input  logic              SDCIntr,
    output logic              MExtInt,
    output logic              SExtInt
);

    // Register Offsets
    localparam PLIC_PRIORITY_SRC1 = 24'h000004; // Priority for Source 1 (UART)
    localparam PLIC_PRIORITY_SRC2 = 24'h000008; // Priority for Source 2 (GPIO)
    localparam PLIC_PRIORITY_SRC3 = 24'h00000C; // Priority for Source 3 (SPI)
    localparam PLIC_PRIORITY_SRC4 = 24'h000010; // Priority for Source 4 (SDC)
    localparam PLIC_PENDING       = 24'h001000;
    localparam PLIC_ENABLE        = 24'h002000;
    localparam PLIC_THRESHOLD     = 24'h200000;
    localparam PLIC_CLAIM         = 24'h200004;

    logic [2:0] priority_src1;
    logic [2:0] priority_src2;
    logic [2:0] priority_src3;
    logic [2:0] priority_src4;
    logic [2:0] threshold;
    logic [4:0] enables; // bit 1: UART, bit 2: GPIO, bit 3: SPI, bit 4: SDC

    wire memwrite = PWRITE & PENABLE & PSEL;
    assign PREADY  = 1'b1;
    assign SExtInt = 1'b0; // Single hart M-mode default

    wire [4:0] pending = {SDCIntr, SPIIntr, GPIOIntr, UARTIntr, 1'b0};

    // Calculate active interrupts above threshold
    wire src1_active = pending[1] & enables[1] & (priority_src1 > threshold);
    wire src2_active = pending[2] & enables[2] & (priority_src2 > threshold);
    wire src3_active = pending[3] & enables[3] & (priority_src3 > threshold);
    wire src4_active = pending[4] & enables[4] & (priority_src4 > threshold);

    // Determine highest priority active interrupt
    logic [2:0] claim_id;
    logic [2:0] max_prio;

    always_comb begin
        claim_id = 3'd0;
        max_prio = threshold;

        if (src1_active && (priority_src1 > max_prio)) begin
            claim_id = 3'd1;
            max_prio = priority_src1;
        end
        if (src2_active && (priority_src2 > max_prio)) begin
            claim_id = 3'd2;
            max_prio = priority_src2;
        end
        if (src3_active && (priority_src3 > max_prio)) begin
            claim_id = 3'd3;
            max_prio = priority_src3;
        end
        if (src4_active && (priority_src4 > max_prio)) begin
            claim_id = 3'd4;
            max_prio = priority_src4;
        end
    end

    // Interrupt output to CPU
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            MExtInt <= 1'b0;
        end else begin
            MExtInt <= (claim_id != 3'd0);
        end
    end

    // APB Read
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA <= 32'd0;
        end else begin
            case (PADDR[23:0])
                PLIC_PRIORITY_SRC1: PRDATA <= {29'b0, priority_src1};
                PLIC_PRIORITY_SRC2: PRDATA <= {29'b0, priority_src2};
                PLIC_PRIORITY_SRC3: PRDATA <= {29'b0, priority_src3};
                PLIC_PRIORITY_SRC4: PRDATA <= {29'b0, priority_src4};
                PLIC_PENDING:       PRDATA <= {27'b0, pending};
                PLIC_ENABLE:        PRDATA <= {27'b0, enables};
                PLIC_THRESHOLD:     PRDATA <= {29'b0, threshold};
                PLIC_CLAIM:         PRDATA <= {29'b0, claim_id};
                default:            PRDATA <= 32'd0;
            endcase
        end
    end

    // APB Write
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            priority_src1 <= 3'd1;
            priority_src2 <= 3'd1;
            priority_src3 <= 3'd1;
            priority_src4 <= 3'd1;
            threshold     <= 3'd0;
            enables       <= 5'd0;
        end else if (memwrite) begin
            case (PADDR[23:0])
                PLIC_PRIORITY_SRC1: priority_src1 <= PWDATA[2:0];
                PLIC_PRIORITY_SRC2: priority_src2 <= PWDATA[2:0];
                PLIC_PRIORITY_SRC3: priority_src3 <= PWDATA[2:0];
                PLIC_PRIORITY_SRC4: priority_src4 <= PWDATA[2:0];
                PLIC_ENABLE:        enables       <= PWDATA[4:0];
                PLIC_THRESHOLD:     threshold     <= PWDATA[2:0];
                default: ;
            endcase
        end
    end

endmodule
