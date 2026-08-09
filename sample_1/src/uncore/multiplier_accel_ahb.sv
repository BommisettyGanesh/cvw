// src/uncore/multiplier_accel_ahb.sv
// 32-Bit Hardware Multiplier Accelerator for AHB-Lite Bus

module multiplier_accel_ahb (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HSEL,
    input  logic [31:0] HADDR,
    input  logic [31:0] HWDATA,
    input  logic        HWRITE,
    input  logic [1:0]  HTRANS,
    input  logic        HREADY,
    output logic [31:0] HRDATA,
    output logic        HREADYOUT,
    output logic [1:0]  HRESP,
    output logic        accel_irq   // Interrupt output to PLIC
);

    // Register Offsets:
    // 0x00: SRC_A     (32-bit multiplicand)
    // 0x04: SRC_B     (32-bit multiplier)
    // 0x08: CTRL      (Bit 0: Start, Bit 2: IRQ Enable)
    // 0x0C: STATUS    (Bit 0: Done)
    // 0x10: RESULT_LO (Lower 32 bits of 64-bit product)
    // 0x14: RESULT_HI (Upper 32 bits of 64-bit product)

    logic [31:0] src_a, src_b, ctrl_reg, status_reg;
    logic [63:0] product_reg;
    logic        write_phase;
    logic [31:0] addr_phase;

    assign HREADYOUT = 1'b1;  // Zero wait-state AHB assertion
    assign HRESP     = 2'b00; // OKAY response

    // AHB Address & Control Phase Latch
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            write_phase <= 1'b0;
            addr_phase  <= 32'h0;
        end else if (HREADY & HSEL & HTRANS[1]) begin
            write_phase <= HWRITE;
            addr_phase  <= HADDR;
        end else begin
            write_phase <= 1'b0;
        end
    end

    // AHB Write Operations (Data Phase)
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            src_a    <= 32'h0;
            src_b    <= 32'h0;
            ctrl_reg <= 32'h0;
        end else if (write_phase) begin
            case (addr_phase[4:0])
                5'h00: src_a    <= HWDATA;
                5'h04: src_b    <= HWDATA;
                5'h08: ctrl_reg <= HWDATA;
            endcase
        end
    end

    // Hardware Multiplier Engine Computation
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            product_reg <= 64'h0;
            status_reg  <= 32'h0;
            accel_irq   <= 1'b0;
        end else if (ctrl_reg[0]) begin // Start bit set
            product_reg <= 64'(src_a) * 64'(src_b); // 32x32 hardware multiplication
            status_reg  <= 32'h1;                  // Done bit set
            accel_irq   <= ctrl_reg[2];            // Pulse interrupt if enabled
        end
    end

    // AHB Read Operations
    always_comb begin
        case (addr_phase[4:0])
            5'h00: HRDATA = src_a;
            5'h04: HRDATA = src_b;
            5'h08: HRDATA = ctrl_reg;
            5'h0C: HRDATA = status_reg;
            5'h10: HRDATA = product_reg[31:0];  // RESULT_LO
            5'h14: HRDATA = product_reg[63:32]; // RESULT_HI
            default: HRDATA = 32'h0;
        endcase
    end

endmodule
