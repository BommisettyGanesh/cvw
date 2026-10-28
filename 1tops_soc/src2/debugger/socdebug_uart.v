//-----------------------------------------------------------------------------
// SoCDebug UART Transceiver with AXI-Stream Interface
// Bridges physical serial line (RX/TX) to ADP Stream interface
// Supports dynamic, glitch-free reconfigurable baud rate clock divider
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module socdebug_uart #(
    parameter CLK_FREQ   = 100_000_000, // Basys 3 100 MHz oscillator
    parameter BAUD_RATE  = 115200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Dynamic Clock Divider (clocks per bit, controlled only via Debugger)
    input  wire [15:0] clks_per_bit_i,

    // Serial Pins
    input  wire        uart_rx,
    output reg         uart_tx,

    // Host to Debugger (RX stream)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,

    // Debugger to Host (TX stream)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready
);

    localparam DEFAULT_CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    //-------------------------------------------------------------------------
    // Synchronous, Glitch-Free Clock Divider Register
    // Only latches when UART RX and TX engines are completely idle
    // Clamped to minimum of 4 cycles to prevent zero/single-cycle lockups
    //-------------------------------------------------------------------------
    reg [15:0] clks_per_bit_reg;

    wire [15:0] clks_per_bit = clks_per_bit_reg;
    wire [15:0] half_bit     = clks_per_bit[15:1]; // clks_per_bit / 2
    wire [15:0] bit_limit    = (clks_per_bit > 16'd1) ? (clks_per_bit - 16'd1) : 16'd0;

    //-------------------------------------------------------------------------
    // RX Synchronizer (2-stage flip-flop for metastability resolution)
    //-------------------------------------------------------------------------
    reg [1:0] rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_sync <= 2'b11;
        else        rx_sync <= {rx_sync[0], uart_rx};
    end
    wire rx_in = rx_sync[1];

    //-------------------------------------------------------------------------
    // RX State Machine
    //-------------------------------------------------------------------------
    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [15:0] rx_clk_cnt;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state      <= RX_IDLE;
            rx_clk_cnt    <= 16'd0;
            rx_bit_idx    <= 3'd0;
            rx_shift_reg  <= 8'h00;
            m_axis_tdata  <= 8'h00;
            m_axis_tvalid <= 1'b0;
        end else begin
            // Handshake clears valid when accepted
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 16'd0;
                    rx_bit_idx <= 3'd0;
                    if (!rx_in) begin // Start bit detected (falling edge)
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_clk_cnt == half_bit) begin
                        if (!rx_in) begin // Valid start bit
                            rx_clk_cnt <= 16'd0;
                            rx_state   <= RX_DATA;
                        end else begin
                            rx_state   <= RX_IDLE; // False glitch
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_cnt < bit_limit) begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end else begin
                        rx_clk_cnt   <= 16'd0;
                        rx_shift_reg <= {rx_in, rx_shift_reg[7:1]};
                        if (rx_bit_idx < 3'd7) begin
                            rx_bit_idx <= rx_bit_idx + 1'b1;
                        end else begin
                            rx_bit_idx <= 3'd0;
                            rx_state   <= RX_STOP;
                        end
                    end
                end

                RX_STOP: begin
                    if (rx_clk_cnt < bit_limit) begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end else begin
                        rx_clk_cnt    <= 16'd0;
                        rx_state      <= RX_IDLE;
                        m_axis_tdata  <= rx_shift_reg;
                        m_axis_tvalid <= 1'b1; // Output byte available
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // TX State Machine
    //-------------------------------------------------------------------------
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [15:0] tx_clk_cnt;
    reg [2:0]  tx_bit_idx;
    reg [7:0]  tx_data_reg;

    assign s_axis_tready = (tx_state == TX_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state        <= TX_IDLE;
            tx_clk_cnt      <= 16'd0;
            tx_bit_idx      <= 3'd0;
            tx_data_reg     <= 8'h00;
            uart_tx         <= 1'b1; // Idle high
            clks_per_bit_reg<= DEFAULT_CLKS_PER_BIT[15:0];
        end else begin
            // Synchronous update of divider only when both engines are idle and no TX is pending
            if (rx_state == RX_IDLE && tx_state == TX_IDLE && !s_axis_tvalid) begin
                if (clks_per_bit_i >= 16'd4) begin
                    clks_per_bit_reg <= clks_per_bit_i;
                end
            end

            case (tx_state)
                TX_IDLE: begin
                    uart_tx    <= 1'b1;
                    tx_clk_cnt <= 16'd0;
                    tx_bit_idx <= 3'd0;
                    if (s_axis_tvalid) begin
                        tx_data_reg <= s_axis_tdata;
                        tx_state    <= TX_START;
                    end
                end

                TX_START: begin
                    uart_tx <= 1'b0; // Start bit
                    if (tx_clk_cnt < bit_limit) begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end else begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    uart_tx <= tx_data_reg[tx_bit_idx];
                    if (tx_clk_cnt < bit_limit) begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end else begin
                        tx_clk_cnt <= 16'd0;
                        if (tx_bit_idx < 3'd7) begin
                            tx_bit_idx <= tx_bit_idx + 1'b1;
                        end else begin
                            tx_bit_idx <= 3'd0;
                            tx_state   <= TX_STOP;
                        end
                    end
                end

                TX_STOP: begin
                    uart_tx <= 1'b1; // Stop bit
                    if (tx_clk_cnt < bit_limit) begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end else begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
