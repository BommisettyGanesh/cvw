////////////////////////////////////////////////////////////////////////////////
// wally_soc_fpga_top.sv
//
// Dedicated Top-Level FPGA Wrapper for CORE-V Wally RISC-V SoC with
// Dual-Protocol Hardware Debugger on Digilent Basys 3 (Artix-7 xc7a35tcpg236-1)
////////////////////////////////////////////////////////////////////////////////

`include "config.vh"
import cvw::*;
`include "parameter-defs.vh"

module wally_soc_fpga_top #(
  parameter CLK_FREQ    = 50_000_000, // 50 MHz SoC clock from on-chip MMCM
  parameter BAUD_RATE   = 115200,     // Debugger UART baud rate
  parameter PROMPT_CHAR = "]",        // ADP CLI prompt
  // NOTE: To auto-prompt ']' on boot without needing 0x1B (ESC), uncomment lines 137 & 737 in src/debugger/socdebug_adp_control.v
  parameter FT_WIDTH    = 1,          // FT1248 bus width (1-bit on Basys 3 PMOD JB)
  parameter FT_CLKDIV   = 8'd1        // SCLK = 50 MHz / (2 * (1 + 1)) = 12.5 MHz FT1248 clock
) (
  // 1. Clock and Reset (Basys 3 Onboard)
  input  logic                clk,              // 100 MHz on-board oscillator (Pin W5)
  input  logic                reset_btn,        // Pushbutton btnC (Pin U18 - Active High)

  // 2. Dual-Protocol Hardware Debugger Pins (On-Board Micro-USB B18/A18)
  input  logic                dbg_sel,          // Slide Switch SW0 (Pin V17: 0=UART, 1=FT1248)
  input  logic                uart_rx,          // USB-UART RX (Pin B18: from host PC)
  output logic                uart_tx,          // USB-UART TX (Pin A18: to host PC)
  output logic                ft1248_clk,       // PMOD JB Pin 1 (Pin A14: SCLK to FT232H)
  output logic                ft1248_ss_n,      // PMOD JB Pin 2 (Pin A16: SS# to FT232H)
  input  logic                ft1248_miso,      // PMOD JB Pin 3 (Pin B15: MISO / RXF# from FT232H)
  inout  wire [FT_WIDTH-1:0]  ft1248_miosio,    // PMOD JB Pin 4 (Pin B16: MIOSIO Data Bus)

  // 3. Uncore Application 16550 UART (Connected to PMOD JA)
  input  logic                UARTSin,          // PMOD JA Pin 1 (Pin J1: from host PC)
  output logic                UARTSout,         // PMOD JA Pin 2 (Pin L2: to host PC)

  // 4. Status LEDs
  output logic                led_core_halted,  // LED 0 (Pin U16: Lit when CPU is halted)
  output logic                led_dbg_sel,       // LED 1 (Pin E19: Reflects SW0 dbg_sel state)
  output logic                led_rx_detect
);

  // -------------------------------------------------------------------------
  // On-Chip Clock Generation: 100 MHz (Pin W5) -> 50 MHz SoC Core Clock
  // -------------------------------------------------------------------------
  wire clk_soc;
  wire mmcm_locked;

`ifdef SYNTHESIS
  wire clk_soc_unbuf;
  wire clk_fb;

  MMCME2_BASE #(
    .BANDWIDTH          ("OPTIMIZED"),
    .CLKFBOUT_MULT_F    (10.0),       // VCO = 100 MHz * 10.0 = 1000 MHz (Valid: 600-1200 MHz)
    .CLKFBOUT_PHASE     (0.0),
    .CLKIN1_PERIOD      (10.0),       // 100 MHz input
    .CLKOUT0_DIVIDE_F   (20.0),       // Output = 1000 MHz / 20.0 = 50.0 MHz
    .CLKOUT0_DUTY_CYCLE (0.5),
    .CLKOUT0_PHASE      (0.0),
    .DIVCLK_DIVIDE      (1),
    .REF_JITTER1        (0.010),
    .STARTUP_WAIT       ("FALSE")
  ) u_mmcm (
    .CLKOUT0            (clk_soc_unbuf),
    .CLKOUT0B           (),
    .CLKOUT1            (),
    .CLKOUT1B           (),
    .CLKOUT2            (),
    .CLKOUT2B           (),
    .CLKOUT3            (),
    .CLKOUT3B           (),
    .CLKOUT4            (),
    .CLKOUT5            (),
    .CLKOUT6            (),
    .CLKFBOUT           (clk_fb),
    .CLKFBOUTB          (),
    .LOCKED             (mmcm_locked),
    .CLKIN1             (clk),
    .PWRDWN             (1'b0),
    .RST                (reset_btn),
    .CLKFBIN            (clk_fb)
  );

  BUFG u_bufg_soc (
    .I (clk_soc_unbuf),
    .O (clk_soc)
  );
`else
  assign clk_soc     = clk;
  assign mmcm_locked = 1'b1;
`endif

  // Active-high external reset for SoC (asserted when reset_btn is pressed OR MMCM not locked)
  wire reset_ext = reset_btn | (~mmcm_locked);
  
  // Visual status LED for protocol switch
  assign led_dbg_sel = dbg_sel;

  // -------------------------------------------------------------------------
  // Synchronous UART RX Monitor & Activity / Character ']' Detector
  // -------------------------------------------------------------------------
  // Baud timing: at 50 MHz SoC clock and 115200 baud, bit period is 434 cycles.
  localparam int UART_CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50_000_000 / 115200 = 434
  localparam int UART_HALF_BIT     = UART_CLKS_PER_BIT / 2; // 217
  localparam int CLK_CNT_W         = $clog2(UART_CLKS_PER_BIT + 1);
  localparam int PULSE_CYCLES      = CLK_FREQ / 5;          // ~200 ms visible blink (10,000,000 cycles)
  localparam [7:0] TARGET_CHAR     = 8'h5D;                 // ASCII ']' (0x5D)

  // 1. Two-stage synchronizer to prevent metastability on asynchronous uart_rx input
  logic [1:0] rx_sync;
  always_ff @(posedge clk_soc) begin
    if (reset_btn) begin
      rx_sync <= 2'b11; // UART idle line state is high
    end else begin
      rx_sync <= {rx_sync[0], uart_rx};
    end
  end
  wire rx_clean = rx_sync[1];

  // 2. Dedicated UART RX Byte Deserializer
  typedef enum logic [1:0] {
    RX_IDLE  = 2'd0,
    RX_START = 2'd1,
    RX_DATA  = 2'd2,
    RX_STOP  = 2'd3
  } rx_state_t;

  rx_state_t              rx_state;
  logic [CLK_CNT_W-1:0]   rx_clk_cnt;
  logic [2:0]             rx_bit_idx;
  logic [7:0]             rx_shift_reg;
  logic [7:0]             rx_byte;
  logic                   rx_byte_valid;

  always_ff @(posedge clk_soc) begin
    if (reset_btn || !mmcm_locked) begin
      rx_state      <= RX_IDLE;
      rx_clk_cnt    <= '0;
      rx_bit_idx    <= '0;
      rx_shift_reg  <= 8'h00;
      rx_byte       <= 8'h00;
      rx_byte_valid <= 1'b0;
    end else begin
      rx_byte_valid <= 1'b0; // Default single-cycle strobe

      case (rx_state)
        RX_IDLE: begin
          rx_clk_cnt <= '0;
          rx_bit_idx <= '0;
          if (!rx_clean) begin // Falling edge indicates potential start bit
            rx_state <= RX_START;
          end
        end

        RX_START: begin
          if (rx_clk_cnt == UART_HALF_BIT) begin
            if (!rx_clean) begin // Valid start bit sampled at midpoint
              rx_clk_cnt <= '0;
              rx_state   <= RX_DATA;
            end else begin
              rx_state   <= RX_IDLE; // Glitch rejection: return to idle
            end
          end else begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end
        end

        RX_DATA: begin
          if (rx_clk_cnt < UART_CLKS_PER_BIT - 1) begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end else begin
            rx_clk_cnt   <= '0;
            rx_shift_reg <= {rx_clean, rx_shift_reg[7:1]}; // LSB first
            if (rx_bit_idx < 3'd7) begin
              rx_bit_idx <= rx_bit_idx + 1'b1;
            end else begin
              rx_bit_idx <= '0;
              rx_state   <= RX_STOP;
            end
          end
        end

        RX_STOP: begin
          if (rx_clk_cnt < UART_CLKS_PER_BIT - 1) begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end else begin
            rx_clk_cnt <= '0;
            rx_state   <= RX_IDLE;
            if (rx_clean) begin // Valid stop bit received (High)
              rx_byte       <= rx_shift_reg;
              rx_byte_valid <= 1'b1;
            end
          end
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // 3. LED Detection Logic
  // - Glows / latches solidly ON when target character ']' (0x5D) is received
  // - Stretches a ~200ms blink whenever ANY valid UART byte is received for immediate visual feedback
  wire char_match = rx_byte_valid && (rx_byte == TARGET_CHAR);
  wire any_byte   = rx_byte_valid;

  logic [23:0] pulse_timer;
  logic        sticky_match;

  always_ff @(posedge clk_soc) begin
    if (reset_btn || !mmcm_locked) begin
      pulse_timer  <= '0;
      sticky_match <= 1'b0;
    end else begin
      // Latch HIGH if target character ']' was detected (sticky until reset)
      if (char_match) begin
        sticky_match <= 1'b1;
      end

      // Pulse stretcher: keeps LED ON for ~200ms when any byte arrives
      if (any_byte) begin
        pulse_timer <= PULSE_CYCLES[23:0];
      end else if (pulse_timer > 0) begin
        pulse_timer <= pulse_timer - 1'b1;
      end
    end
  end

  // Drive LED: Solid ON if ']' detected; Blinks ~200ms on any UART activity
  assign led_rx_detect = sticky_match | (pulse_timer != '0);

  // Unused peripheral ties
  wire        ExternalStall = 1'b0;
  wire        TIMECLK       = 1'b0;
  wire [31:0] GPIOIN        = 32'b0;
  wire [31:0] GPIOOUT;
  wire [31:0] GPIOEN;
  wire        SPIIn         = 1'b0;
  wire        SPIOut;
  wire [3:0]  SPICS;
  wire        SPICLK;
  wire        SDCIn         = 1'b0;
  wire        SDCCmd;
  wire [3:0]  SDCCS;
  wire        SDCCLK;
  wire        HCLK, HRESETn;
  wire [P.PA_BITS-1:0] HADDR;
  wire [P.AHBW-1:0]    HWDATA;
  wire [P.XLEN/8-1:0]  HWSTRB;
  wire                 HWRITE;
  wire [2:0]           HSIZE, HBURST;
  wire [3:0]           HPROT;
  wire [1:0]           HTRANS;
  wire                 HMASTLOCK, HREADY, reset;

  // Instantiate complete SoC with integrated Dual-Protocol Debugger & BRAM memories
  wallypipelinedsoc #(
    .P           (P),
    .CLK_FREQ    (CLK_FREQ),
    .BAUD_RATE   (BAUD_RATE),
    .PROMPT_CHAR (PROMPT_CHAR),
    .FT_WIDTH    (FT_WIDTH),
    .FT_CLKDIV   (FT_CLKDIV)
  ) soc (
    .clk              (clk_soc),
    .reset_ext        (reset_ext),
    .reset            (reset),
    .ExternalStall    (ExternalStall),
    .HCLK             (HCLK),
    .HRESETn          (HRESETn),
    .HADDR            (HADDR),
    .HWDATA           (HWDATA),
    .HWSTRB           (HWSTRB),
    .HWRITE           (HWRITE),
    .HSIZE            (HSIZE),
    .HBURST           (HBURST),
    .HPROT            (HPROT),
    .HTRANS           (HTRANS),
    .HMASTLOCK        (HMASTLOCK),
    .HREADY           (HREADY),
    .TIMECLK          (TIMECLK),
    .GPIOIN           (GPIOIN),
    .GPIOOUT          (GPIOOUT),
    .GPIOEN           (GPIOEN),
    .UARTSin          (UARTSin),
    .UARTSout         (UARTSout),
    .SPIIn            (SPIIn),
    .SPIOut           (SPIOut),
    .SPICS            (SPICS),
    .SPICLK           (SPICLK),
    .SDCIn            (SDCIn),
    .SDCCmd           (SDCCmd),
    .SDCCS            (SDCCS),
    .SDCCLK           (SDCCLK),

    // Debugger Subsystem Pins
    .dbg_sel          (dbg_sel),
    .uart_rx          (uart_rx),
    .uart_tx          (uart_tx),
    .ft1248_clk       (ft1248_clk),
    .ft1248_ss_n      (ft1248_ss_n),
    .ft1248_miso      (ft1248_miso),
    .ft1248_miosio    (ft1248_miosio),
    .core_halted_led  (led_core_halted)
  );

endmodule
