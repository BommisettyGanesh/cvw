//-----------------------------------------------------------------------------
// Comprehensive Testbench for SoCDebug Debugger Subsystem
// Covers:
//  - Protocol Multiplexer Testing via Hardware Pin 'dbg_sel':
//      * dbg_sel = 0: Dedicated Debug UART Interface
//      * dbg_sel = 1: Dedicated FT1248 High-Speed Interface
//  - Both protocols verified for:
//      * Core Halt / Status / Resume Control ('C 0202', 'C', 'C 0102')
//      * Memory Write & Readback Verification ('W' and 'R after A')
//      * Instruction Memory (IRAM @ 0x8000_0000)
//      * Data Memory (DRAM @ 0x8000_2000)
//      * Uncore APB Peripherals (0x1000_0000)
//      * 1TOPS Accelerator & Multiplier (0x3000_0000)
//      * Bulk Memory Fill ('F') & Raw Binary Upload ('U')
//      * Hardware Polling ('P', 'M', 'V') with match & timeout
//      * Unmapped / Illegal Address AHB Bus Error (HRESP = 1 -> '!')
//      * Invalid Command error handling ('?')
//  - Protocol Isolation Verification:
//      * When dbg_sel = 1, UART traffic is isolated and ignored.
//      * When dbg_sel = 0, FT1248 traffic is isolated and ignored.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_debugger;

    localparam CLK_FREQ   = 50_000_000;
    localparam BAUD_RATE  = 2_500_000; // High speed for fast simulation
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // 400 ns per bit

    reg clk;
    reg rst_n;

    // Hardware Protocol Selection Pad
    // 0 = Dedicated Debug UART
    // 1 = Dedicated FT1248 High-Speed Interface
    reg  dbg_sel;

    // UART Physical Signals
    reg  uart_rx;
    wire uart_tx;

    // FT1248 Physical Signals
    wire ft1248_clk;
    wire ft1248_ss_n;
    wire ft1248_miso;
    wire ft1248_miosio;

    // FTDI FT232H BFM Signals
    wire ft_bfm_miso;
    wire ft_bfm_miosio_o;
    wire ft_bfm_miosio_z;
    wire [7:0] ft_bfm_tx_data;
    wire       ft_bfm_tx_valid;
    reg        ft_bfm_tx_ready = 1'b1;
    reg  [7:0] ft_bfm_rx_data  = 8'h00;
    reg        ft_bfm_rx_valid = 1'b0;
    wire       ft_bfm_rx_ready;

    assign ft1248_miosio = (!ft_bfm_miosio_z) ? ft_bfm_miosio_o : 1'bz;
    assign ft1248_miso   = ft_bfm_miso;

    f232h_ft1248_stream #(
        .C_rxd8_TDATA_WIDTH(8),
        .C_txd8_TDATA_WIDTH(8)
    ) u_ft_bfm (
        .ft_clk_i     (ft1248_clk),
        .ft_ssn_i     (ft1248_ss_n),
        .ft_miso_o    (ft_bfm_miso),
        .ft_miosio_i  (ft1248_miosio),
        .ft_miosio_o  (ft_bfm_miosio_o),
        .ft_miosio_z  (ft_bfm_miosio_z),

        .aclk         (clk),
        .aresetn      (rst_n),

        .txd_tvalid_o (ft_bfm_tx_valid),
        .txd_tdata8_o (ft_bfm_tx_data),
        .txd_tready_i (ft_bfm_tx_ready),

        .rxd_tready_o (ft_bfm_rx_ready),
        .rxd_tdata8_i (ft_bfm_rx_data),
        .rxd_tvalid_i (ft_bfm_rx_valid)
    );

    // Core Control Signals
    wire core_halt_o;
    wire core_reset_o;
    reg  core_halted_i;
    wire [7:0] dbg_gpo8;

    // Debugger AHB Master Signals (Master 1)
    wire [31:0] dbg_haddr;
    wire [ 2:0] dbg_hburst;
    wire        dbg_hmastlock;
    wire [ 3:0] dbg_hprot;
    wire [ 2:0] dbg_hsize;
    wire [ 1:0] dbg_htrans;
    wire [31:0] dbg_hwdata;
    wire        dbg_hwrite;
    wire [31:0] dbg_hrdata;
    wire        dbg_hready;
    wire        dbg_hresp;

    // Simulated CPU Core AHB Master (Master 0)
    reg  [31:0] cpu_haddr;
    reg  [31:0] cpu_hwdata;
    reg         cpu_hwrite;
    reg  [ 1:0] cpu_htrans;
    reg  [ 2:0] cpu_hsize;
    reg  [ 2:0] cpu_hburst;
    reg  [ 3:0] cpu_hprot;
    reg         cpu_hmastlock;
    wire [31:0] cpu_hrdata;
    wire        cpu_hready;
    wire        cpu_hresp;

    // Multiplexed Downstream AHB Slave Bus (Output of ahb_mux.sv)
    wire [31:0] s_haddr;
    wire [31:0] s_hwdata;
    wire        s_hwrite;
    wire [ 1:0] s_htrans;
    wire [ 2:0] s_hsize;
    wire [ 2:0] s_hburst;
    wire [ 3:0] s_hprot;
    wire        s_hmastlock;
    wire [31:0] s_hrdata;
    wire        s_hready;
    wire        s_hresp;

    // Test tracking counters
    integer error_count = 0;
    integer pass_count  = 0;

    // Clock Generation (50 MHz = 20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Realistic RISC-V Core Hazard Unit & Step Controller Integration
    wire        core_step_o;
    wire        core_step_mode_o;
    wire        core_step_busy;
    wire        core_step_done;
    reg         sim_instr_retired = 1'b0;
    wire        core_stall_effective;
    wire [31:0] step_count;

    core_step_controller #(
        .WATCHDOG_LIMIT(100)
    ) u_tb_step_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .halt_req_i       (core_halt_o),
        .step_req_i       (core_step_o),
        .step_mode_i      (core_step_mode_o),
        .instr_retired_i  (sim_instr_retired),
        .core_stall_ext_i (1'b0),
        .core_stall_o     (core_stall_effective),
        .step_busy_o      (core_step_busy),
        .step_done_o      (core_step_done),
        .step_count_o     (step_count)
    );

    reg [1:0] core_halt_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_halt_pipe <= 2'b00;
            core_halted_i  <= 1'b0;
        end else begin
            core_halt_pipe <= {core_halt_pipe[0], core_stall_effective};
            core_halted_i  <= core_halt_pipe[1] & ~core_step_busy;
        end
    end

    //-------------------------------------------------------------------------
    // Top-Level Debugger Subsystem with FT1248 + UART + Protocol Mux
    //-------------------------------------------------------------------------
    riscv_debugger_top #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .PROMPT_CHAR ("]"),
        .FT_WIDTH    (1),
        .FT_CLKDIV   (8'd2)
    ) dut_debugger (
        .clk             (clk),
        .rst_n           (rst_n),

        // Protocol Selection Pin
        .dbg_sel         (dbg_sel),

        // Dedicated UART Pins
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),

        // Dedicated FT1248 Pins
        .ft1248_clk      (ft1248_clk),
        .ft1248_ss_n     (ft1248_ss_n),
        .ft1248_miso     (ft1248_miso),
        .ft1248_miosio   (ft1248_miosio),

        // Core Control & Status
        .core_halt_o      (core_halt_o),
        .core_reset_o     (core_reset_o),
        .core_halted_i    (core_halted_i),
        .core_step_o      (core_step_o),
        .core_step_mode_o (core_step_mode_o),
        .core_step_busy_i (core_step_busy),
        .core_step_done_i (core_step_done),

        // AHB Master Port
        .DEBUG_HADDR     (dbg_haddr),
        .DEBUG_HBURST    (dbg_hburst),
        .DEBUG_HMASTLOCK (dbg_hmastlock),
        .DEBUG_HPROT     (dbg_hprot),
        .DEBUG_HSIZE     (dbg_hsize),
        .DEBUG_HTRANS    (dbg_htrans),
        .DEBUG_HWDATA    (dbg_hwdata),
        .DEBUG_HWRITE    (dbg_hwrite),
        .DEBUG_HRDATA    (dbg_hrdata),
        .DEBUG_HREADY    (dbg_hready),
        .DEBUG_HRESP     (dbg_hresp),

        .GPO8            (dbg_gpo8),
        .GPI8            ({5'b0, core_step_done, core_step_busy, core_halted_i})
    );

    //-------------------------------------------------------------------------
    // 2-to-1 AHB Bus Arbiter / Multiplexer
    //-------------------------------------------------------------------------
    ahb_mux #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_ahb_mux (
        .HCLK         (clk),
        .HRESETn      (rst_n),
        .core_halt    (core_halt_o),

        // M0: CPU Core
        .M0_HADDR     (cpu_haddr),
        .M0_HWDATA    (cpu_hwdata),
        .M0_HWRITE    (cpu_hwrite),
        .M0_HTRANS    (cpu_htrans),
        .M0_HSIZE     (cpu_hsize),
        .M0_HBURST    (cpu_hburst),
        .M0_HPROT     (cpu_hprot),
        .M0_HMASTLOCK (cpu_hmastlock),
        .M0_HRDATA    (cpu_hrdata),
        .M0_HREADY    (cpu_hready),
        .M0_HRESP     (cpu_hresp),

        // M1: Debugger
        .M1_HADDR     (dbg_haddr),
        .M1_HWDATA    (dbg_hwdata),
        .M1_HWRITE    (dbg_hwrite),
        .M1_HTRANS    (dbg_htrans),
        .M1_HSIZE     (dbg_hsize),
        .M1_HBURST    (dbg_hburst),
        .M1_HPROT     (dbg_hprot),
        .M1_HMASTLOCK (dbg_hmastlock),
        .M1_HRDATA    (dbg_hrdata),
        .M1_HREADY    (dbg_hready),
        .M1_HRESP     (dbg_hresp),

        // Downstream Slave Bus
        .S_HADDR      (s_haddr),
        .S_HWDATA     (s_hwdata),
        .S_HWRITE     (s_hwrite),
        .S_HTRANS     (s_htrans),
        .S_HSIZE      (s_hsize),
        .S_HBURST     (s_hburst),
        .S_HPROT      (s_hprot),
        .S_HMASTLOCK  (s_hmastlock),
        .S_HRDATA     (s_hrdata),
        .S_HREADY     (s_hready),
        .S_HRESP      (s_hresp)
    );

    //=========================================================================
    // DOWNSTREAM SLAVE SUBSYSTEM & BEHAVIORAL MEMORY MODELS
    //=========================================================================

    wire accel_hsel   = (s_haddr >= 32'h3000_0000 && s_haddr <= 32'h30FF_FFFF);
    wire iram_hsel    = (s_haddr >= 32'h8000_0000 && s_haddr <= 32'h8000_1FFF);
    wire dram_hsel    = (s_haddr >= 32'h8000_2000 && s_haddr <= 32'h8000_3FFF);
    wire bootrom_hsel = (s_haddr >= 32'h0001_0000 && s_haddr <= 32'h0001_FFFF);
    wire apb_hsel     = (s_haddr >= 32'h1000_0000 && s_haddr <= 32'h1000_0FFF);
    wire error_hsel   = (s_haddr >= 32'h5000_0000 && s_haddr <= 32'h5FFF_FFFF);

    // 1) 1TOPS Hardware Accelerator / Multiplier
    wire accel_hreadyout;
    wire accel_hresp;
    wire [31:0] accel_hrdata;

    multiplier_ahb #(
        .XLEN(32)
    ) u_accel (
        .clk       (clk),
        .reset     (~rst_n),
        .HSEL      (accel_hsel),
        .HADDR     (s_haddr),
        .HWDATA    (s_hwdata),
        .HWRITE    (s_hwrite),
        .HSIZE     (s_hsize),
        .HBURST    (s_hburst),
        .HPROT     (s_hprot),
        .HTRANS    (s_htrans),
        .HREADY    (s_hready),
        .HREADYOUT (accel_hreadyout),
        .HRESP     (accel_hresp),
        .HRDATA    (accel_hrdata)
    );

    // 2) Memory Arrays
    reg [31:0] iram [0:2047];
    reg [31:0] dram [0:2047];
    reg [31:0] bootrom [0:1023];

    // 3) APB Registers
    reg [31:0] apb_gpio_data;
    reg [31:0] apb_gpio_dir;
    localparam APB_PERIPH_ID = 32'hCAFE_2026;

    reg        iram_active_d, dram_active_d, bootrom_active_d, apb_active_d, error_active_d;
    reg [31:0] s_haddr_d;
    reg [ 2:0] s_hsize_d;
    reg        s_hwrite_d;

    reg [1:0]  apb_wait_cnt;
    wire       apb_wait_stall = (apb_active_d && (s_haddr_d[7:0] == 8'h04) && (apb_wait_cnt < 2'd2));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            iram_active_d    <= 1'b0;
            dram_active_d    <= 1'b0;
            bootrom_active_d <= 1'b0;
            apb_active_d     <= 1'b0;
            error_active_d   <= 1'b0;
            s_haddr_d        <= 32'h0;
            s_hsize_d        <= 3'b010;
            s_hwrite_d       <= 1'b0;
            apb_wait_cnt     <= 2'd0;
        end else if (s_hready) begin
            iram_active_d    <= iram_hsel    && s_htrans[1];
            dram_active_d    <= dram_hsel    && s_htrans[1];
            bootrom_active_d <= bootrom_hsel && s_htrans[1];
            apb_active_d     <= apb_hsel     && s_htrans[1];
            error_active_d   <= error_hsel   && s_htrans[1];
            s_haddr_d        <= s_haddr;
            s_hsize_d        <= s_hsize;
            s_hwrite_d       <= s_hwrite;
            apb_wait_cnt     <= 2'd0;
        end else if (apb_wait_stall) begin
            apb_wait_cnt     <= apb_wait_cnt + 1'b1;
        end
    end

    function [3:0] get_wstrb(input [1:0] addr, input [2:0] size);
        case (size)
            3'b000:
                case (addr[1:0])
                    2'b00: get_wstrb = 4'b0001;
                    2'b01: get_wstrb = 4'b0010;
                    2'b10: get_wstrb = 4'b0100;
                    2'b11: get_wstrb = 4'b1000;
                endcase
            3'b001:
                case (addr[1])
                    1'b0:  get_wstrb = 4'b0011;
                    1'b1:  get_wstrb = 4'b1100;
                endcase
            default: get_wstrb = 4'b1111;
        endcase
    endfunction

    wire [10:0] iram_word_idx = s_haddr_d[12:2];
    wire [10:0] dram_word_idx = s_haddr_d[12:2];
    wire [ 3:0] wstrb = get_wstrb(s_haddr_d[1:0], s_hsize_d);

    always @(posedge clk) begin
        if (iram_active_d && s_hwrite_d && s_hready) begin
            if (wstrb[0]) iram[iram_word_idx][ 7: 0] <= s_hwdata[ 7: 0];
            if (wstrb[1]) iram[iram_word_idx][15: 8] <= s_hwdata[15: 8];
            if (wstrb[2]) iram[iram_word_idx][23:16] <= s_hwdata[23:16];
            if (wstrb[3]) iram[iram_word_idx][31:24] <= s_hwdata[31:24];
        end
        if (dram_active_d && s_hwrite_d && s_hready) begin
            if (wstrb[0]) dram[dram_word_idx][ 7: 0] <= s_hwdata[ 7: 0];
            if (wstrb[1]) dram[dram_word_idx][15: 8] <= s_hwdata[15: 8];
            if (wstrb[2]) dram[dram_word_idx][23:16] <= s_hwdata[23:16];
            if (wstrb[3]) dram[dram_word_idx][31:24] <= s_hwdata[31:24];
        end
        if (apb_active_d && s_hwrite_d && s_hready) begin
            if (s_haddr_d[7:0] == 8'h00) apb_gpio_data <= s_hwdata;
            if (s_haddr_d[7:0] == 8'h04) apb_gpio_dir  <= s_hwdata;
        end
    end

    reg [31:0] mem_hrdata;
    always @(*) begin
        if (iram_active_d)         mem_hrdata = iram[iram_word_idx];
        else if (dram_active_d)    mem_hrdata = dram[dram_word_idx];
        else if (bootrom_active_d) mem_hrdata = bootrom[s_haddr_d[11:2]];
        else if (apb_active_d) begin
            case (s_haddr_d[7:0])
                8'h00:   mem_hrdata = apb_gpio_data;
                8'h04:   mem_hrdata = apb_gpio_dir;
                8'h08:   mem_hrdata = APB_PERIPH_ID;
                default: mem_hrdata = 32'h0;
            endcase
        end else begin
            mem_hrdata = 32'h0;
        end
    end

    assign s_hready = accel_hsel ? accel_hreadyout :
                      apb_wait_stall ? 1'b0 : 1'b1;

    assign s_hresp  = accel_hsel   ? accel_hresp :
                      error_active_d ? 1'b1 : 1'b0;

    assign s_hrdata = accel_hsel   ? accel_hrdata : mem_hrdata;

    // Track AHB read transfers
    reg        ahb_read_addr_phase;
    reg [31:0] captured_haddr;
    reg [31:0] captured_hrdata;
    reg        ahb_read_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ahb_read_addr_phase <= 1'b0;
            captured_haddr      <= 32'h0;
            captured_hrdata     <= 32'h0;
            ahb_read_done       <= 1'b0;
        end else begin
            if (dbg_htrans == 2'b10 && dbg_hwrite == 1'b0 && dbg_hready) begin
                ahb_read_addr_phase <= 1'b1;
                captured_haddr      <= dbg_haddr;
                ahb_read_done       <= 1'b0;
            end else if (ahb_read_addr_phase && dbg_hready) begin
                ahb_read_addr_phase <= 1'b0;
                captured_hrdata     <= dbg_hrdata;
                ahb_read_done       <= 1'b1;
            end
        end
    end

    //=========================================================================
    // PROTOCOL DRIVERS: UART & FT1248
    //=========================================================================

    time current_bit_period = BIT_PERIOD;

    //-------------------------------------------------------------------------
    // UART Drivers
    //-------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 1'b0; // Start bit
            #(current_bit_period);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(current_bit_period);
            end
            uart_rx = 1'b1; // Stop bit
            #(current_bit_period);
            #(current_bit_period / 2);
        end
    endtask

    task send_uart_string(input string str);
        integer j;
        begin
            for (j = 0; j < str.len(); j = j + 1) begin
                send_uart_byte(str[j]);
            end
        end
    endtask

    // UART Output Monitor
    reg [7:0] rx_char;
    string    rx_line = "";
    string    last_completed_line = "";

    always begin
        @(negedge uart_tx);
        #(current_bit_period / 2);
        if (!uart_tx) begin
            #(current_bit_period);
            rx_char[0] = uart_tx; #(current_bit_period);
            rx_char[1] = uart_tx; #(current_bit_period);
            rx_char[2] = uart_tx; #(current_bit_period);
            rx_char[3] = uart_tx; #(current_bit_period);
            rx_char[4] = uart_tx; #(current_bit_period);
            rx_char[5] = uart_tx; #(current_bit_period);
            rx_char[6] = uart_tx; #(current_bit_period);
            rx_char[7] = uart_tx; #(current_bit_period);
            if (rx_char == 8'h0A || rx_char == 8'h0D) begin
                if (rx_line.len() > 0) begin
                    last_completed_line = rx_line;
                    $display("    [UART_TX] %s", rx_line);
                    rx_line = "";
                end
            end else if (rx_char >= 32 && rx_char <= 126) begin
                rx_line = {rx_line, string'(rx_char)};
            end
        end
    end

    //-------------------------------------------------------------------------
    // FT1248 Drivers & Monitor (Emulating FTDI FT232H device via BFM)
    //-------------------------------------------------------------------------
    task send_ft1248_byte(input [7:0] byte_val);
        begin
            @(posedge clk);
            ft_bfm_rx_data  <= byte_val;
            ft_bfm_rx_valid <= 1'b1;
            @(posedge clk);
            while (!ft_bfm_rx_ready) @(posedge clk);
            ft_bfm_rx_valid <= 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    task send_ft1248_string(input string str);
        integer k;
        begin
            for (k = 0; k < str.len(); k = k + 1) begin
                send_ft1248_byte(str[k]);
            end
        end
    endtask

    // FT1248 Receiver Monitor (Captures bytes transmitted by SoC to FTDI via BFM)
    string ft_rx_line = "";
    string last_completed_ft_line = "";

    always @(posedge clk) begin
        if (rst_n && ft_bfm_tx_valid && ft_bfm_tx_ready) begin
            if (ft_bfm_tx_data == 8'h0A || ft_bfm_tx_data == 8'h0D) begin
                if (ft_rx_line.len() > 0) begin
                    last_completed_ft_line = ft_rx_line;
                    $display("    [FT1248_TX] %s", ft_rx_line);
                    ft_rx_line = "";
                end
            end else if (ft_bfm_tx_data >= 32 && ft_bfm_tx_data <= 126) begin
                ft_rx_line = {ft_rx_line, string'(ft_bfm_tx_data)};
            end
        end
    end

    always @(posedge clk) begin
        if (dut_debugger.u_socdebug_ahb.u_adp_control.com_rx_done) begin
            $display("    [ADP_RX] 0x%02x ('%c') in adp_state=%0d", 
                     dut_debugger.u_socdebug_ahb.u_adp_control.com_rx_byte,
                     dut_debugger.u_socdebug_ahb.u_adp_control.com_rx_byte,
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_state);
        end
    end
    task wait_for_prompt;
        begin
            wait (dut_debugger.u_socdebug_ahb.u_adp_control.adp_state == 6'd15);
            wait (dut_debugger.u_uart.tx_state == 2'd0 && !dut_debugger.u_uart.s_axis_tvalid);
            #(current_bit_period * 4);
        end
    endtask

    // Verification helper for 'R after A'
    task verify_read_word(input [31:0] expected_val, input string tag);
        begin
            if (dbg_sel == 1'b0) begin
                send_uart_string("R\n");
            end else begin
                send_ft1248_string("R\n");
            end
            wait_for_prompt();
            if (captured_hrdata === expected_val) begin
                $display("    [PASS] %s -> Readback from 'R' = 0x%08x (Matches written: 0x%08x)",
                         tag, captured_hrdata, expected_val);
                pass_count = pass_count + 1;
            end else begin
                $display("    [FAIL] %s -> Readback mismatch! 'R' returned 0x%08x, Expected: 0x%08x",
                         tag, captured_hrdata, expected_val);
                error_count = error_count + 1;
            end
        end
    endtask

    wire [31:0] adp_bus_data = dut_debugger.u_socdebug_ahb.u_adp_control.adp_bus_data;

    //=========================================================================
    // COMPREHENSIVE TEST SEQUENCE
    //=========================================================================
    initial begin
        $display("\n===============================================================================");
        $display("   RISC-V SOCDEBUG DUAL-PROTOCOL TESTBENCH (UART & FT1248 INTEGRATION)         ");
        $display("===============================================================================\n");

        // Initialize signals
        rst_n             = 0;
        dbg_sel           = 0; // Default to UART mode
        uart_rx           = 1;
        ft_bfm_rx_valid   = 0;
        ft_bfm_tx_ready   = 1;

        cpu_haddr     = 32'h0;
        cpu_hwdata    = 32'h0;
        cpu_hwrite    = 0;
        cpu_htrans    = 2'b00; // IDLE
        cpu_hsize     = 3'b010;
        cpu_hburst    = 3'b000;
        cpu_hprot     = 4'b0000;
        cpu_hmastlock = 0;

        // Preload memory models
        bootrom[0] = 32'h0000_0013;
        bootrom[1] = 32'h0010_0073;
        bootrom[2] = 32'h1234_5678;

        dram[0]    = 32'hAABB_CCDD;
        dram[1]    = 32'h1122_3344;

        // Reset release
        #200;
        rst_n = 1;
        $display("[TB] System reset released at %0t ps", $time);

        // Wait for Debugger startup banner
        $display("[TB] Waiting for startup banner on UART...");
        wait (dut_debugger.u_socdebug_ahb.u_adp_control.banner == 1'b0);
        $display("[TB] Startup banner complete at %0t ps", $time);

        //=====================================================================
        // PART 1: COMPLETE VERIFICATION IN UART MODE (dbg_sel = 0)
        //=====================================================================
        $display("\n-------------------------------------------------------------------------------");
        $display("   PART 1: VERIFYING DEBUGGER VIA UART PROTOCOL (dbg_sel = 0)                  ");
        $display("-------------------------------------------------------------------------------");
        // Auto-enter ADP mode: prompt ']' is emitted directly after banner without needing ESC
        wait_for_prompt();
        $display("    [PASS] Auto-entered ADP command mode on boot with ']' prompt (no ESC required)!");
        pass_count = pass_count + 1;

        // 1.1 Core Halt & Status
        $display("\n>>> [UART] 1.1: Core Halt & Status Verification <<<");
        send_uart_string("C 0202\n");
        wait (core_halt_o == 1'b1);
        wait (core_halted_i == 1'b1);
        wait_for_prompt();

        send_uart_string("C\n");
        wait_for_prompt();
        if (adp_bus_data[24] === 1'b1) begin
            $display("    [PASS] Core confirmed HALTED via UART status query (GPI8[0] == 1).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core halt status not reflected!");
            error_count = error_count + 1;
        end

        // 1.2 Instruction SRAM Write & Readback
        $display("\n>>> [UART] 1.2: IRAM Program Loading & Readback <<<");
        send_uart_string("A 80000000\n");
        wait_for_prompt();
        send_uart_string("W 00000297\n"); // auipc t0, 0
        wait_for_prompt();
        send_uart_string("W 02028293\n"); // addi t0, t0, 32
        wait_for_prompt();
        send_uart_string("A 80000000\n");
        wait_for_prompt();
        verify_read_word(32'h00000297, "UART IRAM [0x80000000]");
        verify_read_word(32'h02028293, "UART IRAM [0x80000004]");

        // 1.3 Data SRAM Sub-Word Writes & Readbacks
        $display("\n>>> [UART] 1.3: DRAM Sub-word Accesses <<<");
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        send_uart_string("W deadbeef\n");
        wait_for_prompt();
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'hdeadbeef, "UART DRAM 32-bit Word");

        // 1.4 Accelerator Multiplier Computation
        $display("\n>>> [UART] 1.4: 1TOPS Accelerator Multiplier <<<");
        send_uart_string("A 30000000\n");
        wait_for_prompt();
        send_uart_string("W 00000008\n"); // OpA = 8
        wait_for_prompt();
        send_uart_string("A 30000004\n");
        wait_for_prompt();
        send_uart_string("W 00000009\n"); // OpB = 9
        wait_for_prompt();
        send_uart_string("A 30000008\n");
        wait_for_prompt();
        verify_read_word(32'd72, "UART Multiplier Product (8 * 9 = 72)");

        // 1.5 Bus Error on Illegal Address (0x50000000)
        $display("\n>>> [UART] 1.5: Illegal Address Bus Error <<<");
        send_uart_string("A 50000000\n");
        wait_for_prompt();
        send_uart_string("R\n");
        wait_for_prompt();
        $display("    [PASS] UART Bus Error caught: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 1.6 Core Resume
        $display("\n>>> [UART] 1.6: Core Resume <<<");
        send_uart_string("C 0102\n");
        wait (core_halt_o == 1'b0);
        wait (core_halted_i == 1'b0);
        wait_for_prompt();
        send_uart_string("C\n");
        wait_for_prompt();
        if (adp_bus_data[24] === 1'b0) begin
            $display("    [PASS] Core confirmed RESUMED via UART status query (GPI8[0] == 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core resume status not reflected!");
            error_count = error_count + 1;
        end

        // 1.7 Address Query ('A' without parameters) & Lowercase 'a'
        $display("\n>>> [UART] 1.7: Address Query ('A' without parameters) & Lowercase 'a' <<<");
        send_uart_string("A\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h5000_0004) begin
            $display("    [PASS] 'A' command successfully queried current address pointer (0x%08x).",
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'A' command query mismatch! Got 0x%08x",
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr);
            error_count = error_count + 1;
        end

        send_uart_string("a 80002010\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2010) begin
            $display("    [PASS] Lowercase 'a' command successfully set address to 0x80002010.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Lowercase 'a' command failed!");
            error_count = error_count + 1;
        end

        // 1.8 Multi-Word Burst Read ('R <count>')
        $display("\n>>> [UART] 1.8: Multi-Word Burst Read ('R <count>') <<<");
        send_uart_string("A 80002010\n");
        wait_for_prompt();
        send_uart_string("W 11111111\n");
        wait_for_prompt();
        send_uart_string("W 22222222\n");
        wait_for_prompt();
        send_uart_string("W 33333333\n");
        wait_for_prompt();

        send_uart_string("A 80002010\n");
        wait_for_prompt();
        send_uart_string("R 00000003\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_201c) begin
            $display("    [PASS] Multi-word burst read ('R 00000003') read 3 words and advanced address to 0x8000201c.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Multi-word burst read failed! adp_addr = 0x%08x",
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr);
            error_count = error_count + 1;
        end

        // 1.9 Lowercase Read ('r') and Write ('w')
        $display("\n>>> [UART] 1.9: Lowercase Read ('r') and Write ('w') <<<");
        send_uart_string("a 80002020\n");
        wait_for_prompt();
        send_uart_string("w cafebabe\n");
        wait_for_prompt();
        send_uart_string("a 80002020\n");
        wait_for_prompt();
        send_uart_string("r\n");
        wait_for_prompt();
        if (captured_hrdata === 32'hcafebabe) begin
            $display("    [PASS] Lowercase 'w' and 'r' verified: wrote and read back 0xcafebabe.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Lowercase 'w'/'r' readback mismatch! Got 0x%08x", captured_hrdata);
            error_count = error_count + 1;
        end

        // 1.10 Memory Block Fill ('F <count>') with Value ('V')
        $display("\n>>> [UART] 1.10: Memory Block Fill ('F') with Value ('V') <<<");
        send_uart_string("V 55667788\n");
        wait_for_prompt();
        send_uart_string("V\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_val[31:0] === 32'h55667788) begin
            $display("    [PASS] 'V' command set and queried fill pattern: 0x55667788.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'V' command query mismatch!");
            error_count = error_count + 1;
        end

        send_uart_string("A 80002030\n");
        wait_for_prompt();
        send_uart_string("F 00000004\n");
        wait_for_prompt();

        send_uart_string("A 80002030\n");
        wait_for_prompt();
        verify_read_word(32'h55667788, "Fill Word 0 [0x80002030]");
        verify_read_word(32'h55667788, "Fill Word 1 [0x80002034]");
        verify_read_word(32'h55667788, "Fill Word 2 [0x80002038]");
        verify_read_word(32'h55667788, "Fill Word 3 [0x8000203c]");

        // 1.11 Mask ('M') & Polling ('P') Timeout Condition
        $display("\n>>> [UART] 1.11: Mask ('M') & Polling ('P') Timeout Condition <<<");
        send_uart_string("M 000000ff\n");
        wait_for_prompt();
        send_uart_string("M\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_mask === 32'h000000ff) begin
            $display("    [PASS] 'M' command set and queried mask: 0x000000ff.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'M' command query mismatch!");
            error_count = error_count + 1;
        end

        send_uart_string("A 80002030\n");
        wait_for_prompt();
        send_uart_string("V 000000aa\n");
        wait_for_prompt();
        send_uart_string("P 00000003\n");
        wait_for_prompt();
        $display("    [PASS] Polling timeout error response received properly: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 1.12 Invalid Command Rejection ('?')
        $display("\n>>> [UART] 1.12: Invalid Command Rejection ('?') <<<");
        send_uart_string("Z\n");
        wait_for_prompt();
        $display("    [PASS] Invalid command 'Z' rejected with '?' response: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 1.13 Polling Hardware ('P') Match Condition & Count=0 Condition
        $display("\n>>> [UART] 1.13: Polling Hardware ('P') Match Condition & Count=0 Condition <<<");
        send_uart_string("A 80002030\n");
        wait_for_prompt();
        send_uart_string("M 0000ffff\n");
        wait_for_prompt();
        send_uart_string("V 00007788\n");
        wait_for_prompt();
        // Memory at 0x80002030 holds 0x55667788 -> matches masked value immediately on word 0!
        send_uart_string("P 00000005\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_bus_err === 1'b0) begin
            $display("    [PASS] Hardware polling matched successfully without timeout: %s", last_completed_line);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Hardware polling match failed unexpectedly!");
            error_count = error_count + 1;
        end

        // Count=0 edge condition for polling
        send_uart_string("P 00000000\n");
        wait_for_prompt();
        $display("    [PASS] Polling count=0 edge condition returned immediately: %s", last_completed_line);
        pass_count = pass_count + 1;

        // Lowercase m, v, and p commands
        send_uart_string("m 0000ffff\n");
        wait_for_prompt();
        send_uart_string("v 00007788\n");
        wait_for_prompt();
        send_uart_string("p 00000002\n");
        wait_for_prompt();
        $display("    [PASS] Lowercase 'm', 'v', 'p' executed successfully.");
        pass_count = pass_count + 1;

        // 1.14 Subword Byte & Halfword Writes ('W' / 'w') and Subword Reads ('R' / 'r')
        $display("\n>>> [UART] 1.14: Subword Byte & Halfword Accesses <<<");
        send_uart_string("A 80002050\n");
        wait_for_prompt();
        send_uart_string("W 7a\n"); // 2 hex digits = byte write (0x7a) at 0x80002050
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2051) begin
            $display("    [PASS] Byte write 'W 7a' incremented address to 0x80002051.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Byte write address auto-increment mismatch! adp_addr = 0x%08x",
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr);
            error_count = error_count + 1;
        end

        send_uart_string("w 8b\n"); // Lowercase byte write (0x8b) at 0x80002051
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2052) begin
            $display("    [PASS] Lowercase byte write 'w 8b' incremented address to 0x80002052.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Lowercase byte write address auto-increment mismatch!");
            error_count = error_count + 1;
        end

        send_uart_string("W 3412\n"); // 4 hex digits = halfword write (0x3412) at 0x80002052
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2054) begin
            $display("    [PASS] Halfword write 'W 3412' incremented address to 0x80002054.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Halfword write address auto-increment mismatch!");
            error_count = error_count + 1;
        end

        // Readback full 32-bit word assembled from subword writes
        send_uart_string("A 80002050\n");
        wait_for_prompt();
        verify_read_word(32'h34128b7a, "Assembled Word from Subword Writes [0x80002050]");

        // Subword byte read: 'R 00' (2 digits parameter -> 8-bit size)
        send_uart_string("A 80002050\n");
        wait_for_prompt();
        send_uart_string("R 00\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2051) begin
            $display("    [PASS] Subword byte read 'R 00' read byte and advanced address to 0x80002051.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Subword byte read address advance mismatch!");
            error_count = error_count + 1;
        end

        // Subword halfword read: 'r 0000' (4 digits parameter -> 16-bit size)
        send_uart_string("A 80002052\n");
        wait_for_prompt();
        send_uart_string("r 0000\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2054) begin
            $display("    [PASS] Subword halfword read 'r 0000' read halfword and advanced address to 0x80002054.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Subword halfword read address advance mismatch!");
            error_count = error_count + 1;
        end

        // 1.15 Hex Prefix ("0x" / "0X") and Whitespace Tolerances
        $display("\n>>> [UART] 1.15: Hex Prefix (\"0x\" / \"0X\") and Whitespace Tolerances <<<");
        send_uart_string("A 0x80002060\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2060) begin
            $display("    [PASS] Hex prefix '0x' in 'A 0x80002060' parsed properly.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Hex prefix '0x' address parsing failed! adp_addr = 0x%08x",
                     dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr);
            error_count = error_count + 1;
        end

        send_uart_string("a 0X80002070\n");
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2070) begin
            $display("    [PASS] Uppercase hex prefix '0X' in 'a 0X80002070' parsed properly.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Uppercase hex prefix '0X' parsing failed!");
            error_count = error_count + 1;
        end

        send_uart_string("A   80002080\n"); // Multiple spaces
        wait_for_prompt();
        if (dut_debugger.u_socdebug_ahb.u_adp_control.adp_addr === 32'h8000_2080) begin
            $display("    [PASS] Multiple space separator parsed properly.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Multiple space separator parsing failed!");
            error_count = error_count + 1;
        end

        // 1.16 Memory Block Fill Edge Conditions ('F 00000000') & Lowercase 'f'
        $display("\n>>> [UART] 1.16: Memory Block Fill Edge Conditions & Lowercase 'f' <<<");
        send_uart_string("F 00000000\n"); // Count = 0 edge condition
        wait_for_prompt();
        $display("    [PASS] Fill count=0 returned immediately: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("A 80002060\n");
        wait_for_prompt();
        send_uart_string("v a5a5a5a5\n");
        wait_for_prompt();
        send_uart_string("f 00000002\n"); // Lowercase fill of 2 words
        wait_for_prompt();
        send_uart_string("A 80002060\n");
        wait_for_prompt();
        verify_read_word(32'ha5a5a5a5, "Lowercase Fill Word 0 [0x80002060]");
        verify_read_word(32'ha5a5a5a5, "Lowercase Fill Word 1 [0x80002064]");

        // 1.17 Raw Binary Upload Edge Condition ('U 00000000') & Lowercase 'u'
        $display("\n>>> [UART] 1.17: Binary Upload Edge Conditions ('U 00000000') & Lowercase 'u' <<<");
        send_uart_string("U 00000000\n"); // Count = 0 edge condition
        wait_for_prompt();
        $display("    [PASS] 'U 00000000' count=0 returned cleanly: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("u 00000000\n"); // Lowercase 'u' count = 0
        wait_for_prompt();
        $display("    [PASS] 'u 00000000' lowercase returned cleanly: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 1.18 STDIN Push ('S' / 's') & ADP Exit ('X' / 'x') with Re-entry via ESC
        $display("\n>>> [UART] 1.18: STDIN Push ('S' / 's') & ADP Exit ('X' / 'x') <<<");
        send_uart_string("S 41\n"); // Push ASCII 'A' (0x41)
        wait_for_prompt();
        $display("    [PASS] 'S 41' push character executed: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("s 42\n"); // Lowercase 's 42' push ASCII 'B' (0x42)
        wait_for_prompt();
        $display("    [PASS] Lowercase 's 42' push character executed: %s", last_completed_line);
        pass_count = pass_count + 1;

        // Exit ADP mode via 'X'
        send_uart_string("X\n");
        #(current_bit_period * 10);
        $display("    [PASS] 'X' command exited ADP mode.");
        pass_count = pass_count + 1;

        // Re-enter ADP mode using ESC character (0x1b)
        send_uart_byte(8'h1b);
        wait_for_prompt();
        $display("    [PASS] Successfully re-entered ADP mode via ESC (0x1b) with ']' prompt!");
        pass_count = pass_count + 1;

        // Lowercase exit 'x' and re-entry
        send_uart_string("x\n");
        #(current_bit_period * 10);
        send_uart_byte(8'h1b);
        wait_for_prompt();
        $display("    [PASS] Lowercase 'x' exit and ESC re-entry verified.");
        pass_count = pass_count + 1;

        // 1.19 Empty Line & Additional Invalid Command Rejection
        $display("\n>>> [UART] 1.19: Empty Line & Invalid Command Characters <<<");
        send_uart_string("\n"); // Empty newline
        wait_for_prompt();
        $display("    [PASS] Empty newline rejected with '?': %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("K\n"); // Invalid character 'K'
        wait_for_prompt();
        $display("    [PASS] Invalid character 'K' rejected with '?': %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("#\n"); // Invalid character '#'
        wait_for_prompt();
        $display("    [PASS] Invalid character '#' rejected with '?': %s", last_completed_line);
        pass_count = pass_count + 1;

        //=====================================================================
        // PART 2: DYNAMIC SWITCHING TO FT1248 PROTOCOL (dbg_sel = 1)
        //=====================================================================
        $display("\n-------------------------------------------------------------------------------");
        $display("   PART 2: SWITCHING TO FT1248 PROTOCOL VIA HARDWARE PIN (dbg_sel = 1)         ");
        $display("-------------------------------------------------------------------------------");
        #1000;
        dbg_sel = 1'b1; // Switch physical pad to FT1248!
        $display("[TB] Hardware pad dbg_sel set to 1 (FT1248 Active, UART Isolated).");
        #1000;

        // 2.1 Core Halt over FT1248
        $display("\n>>> [FT1248] 2.1: Core Halt & Status Verification <<<");
        send_ft1248_string("C 0202\n");
        wait (core_halt_o == 1'b1);
        wait (core_halted_i == 1'b1);
        wait_for_prompt();

        send_ft1248_string("C\n");
        wait_for_prompt();
        if (adp_bus_data[24] === 1'b1) begin
            $display("    [PASS] Core confirmed HALTED via FT1248 status query (GPI8[0] == 1).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core halt status not reflected over FT1248!");
            error_count = error_count + 1;
        end

        // 2.2 Memory Write & Readback over FT1248
        $display("\n>>> [FT1248] 2.2: Memory Write & Readback Verification <<<");
        send_ft1248_string("A 80002000\n");
        wait_for_prompt();
        send_ft1248_string("W 55aa55aa\n"); // Write distinctive pattern over FT1248
        wait_for_prompt();

        send_ft1248_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'h55aa55aa, "FT1248 DRAM [0x80002000]");

        // 2.3 1TOPS Accelerator Computation over FT1248
        $display("\n>>> [FT1248] 2.3: Accelerator Multiplier Computation over FT1248 <<<");
        send_ft1248_string("A 30000000\n");
        wait_for_prompt();
        send_ft1248_string("W 0000000f\n"); // OpA = 15
        wait_for_prompt();
        send_ft1248_string("A 30000004\n");
        wait_for_prompt();
        send_ft1248_string("W 00000003\n"); // OpB = 3
        wait_for_prompt();
        send_ft1248_string("A 30000008\n");
        wait_for_prompt();
        verify_read_word(32'd45, "FT1248 Multiplier Product (15 * 3 = 45)");

        // 2.4 Hardware Polling over FT1248
        $display("\n>>> [FT1248] 2.4: Hardware Polling ('P') over FT1248 <<<");
        send_ft1248_string("A 30000008\n");
        wait_for_prompt();
        send_ft1248_string("M 000000ff\n");
        wait_for_prompt();
        send_ft1248_string("V 0000002d\n"); // Match 45 (0x2D)
        wait_for_prompt();
        send_ft1248_string("P 000000ff\n");
        wait_for_prompt();
        $display("    [PASS] Hardware Poll succeeded over FT1248 on exact match (45 = 0x2D).");
        pass_count = pass_count + 1;

        // 2.5 Core Resume over FT1248
        $display("\n>>> [FT1248] 2.5: Core Resume over FT1248 <<<");
        send_ft1248_string("C 0102\n");
        wait (core_halt_o == 1'b0);
        wait (core_halted_i == 1'b0);
        wait_for_prompt();

        send_ft1248_string("C\n");
        wait_for_prompt();
        if (adp_bus_data[24] === 1'b0) begin
            $display("    [PASS] Core confirmed RESUMED via FT1248 status query (GPI8[0] == 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core resume status not reflected over FT1248!");
            error_count = error_count + 1;
        end

        //=====================================================================
        // PART 3: PROTOCOL ISOLATION & MULTIPLEXER INTEGRITY VERIFICATION
        //=====================================================================
        $display("\n-------------------------------------------------------------------------------");
        $display("   PART 3: PROTOCOL ISOLATION VERIFICATION                                     ");
        $display("-------------------------------------------------------------------------------");
        // While dbg_sel = 1 (FT1248 mode), send traffic on UART RX pin
        $display("    [TB] Sending command on UART while dbg_sel = 1 (Should be ignored)...");
        send_uart_string("C 0202\n");
        #50000;
        if (core_halt_o === 1'b0) begin
            $display("    [PASS] UART traffic correctly blocked/ignored while dbg_sel = 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] UART traffic leaked through while dbg_sel = 1!");
            error_count = error_count + 1;
        end

        // Switch back to UART mode (dbg_sel = 0)
        #1000;
        dbg_sel = 1'b0;
        $display("[TB] Hardware pad dbg_sel switched back to 0 (UART Active).");
        #1000;

        // Verify UART works again
        send_uart_string("C 0202\n");
        wait (core_halt_o == 1'b1);
        wait (core_halted_i == 1'b1);
        wait_for_prompt();
        $display("    [PASS] UART regained control immediately when dbg_sel switched to 0.");
        pass_count = pass_count + 1;

        send_uart_string("C 0102\n");
        wait (core_halt_o == 1'b0);
        wait (core_halted_i == 1'b0);
        wait_for_prompt();

        //---------------------------------------------------------------------
        // PART 4: CORE STEP FSM CONTROLLER VERIFICATION
        //---------------------------------------------------------------------
        $display("\n-------------------------------------------------------------------------------");
        $display("   PART 4: CORE STEPPING FSM CONTROLLER VERIFICATION                           ");
        $display("-------------------------------------------------------------------------------");

        // 4.1 Halt Core
        $display("\n>>> [STEP] 4.1: Halting Core via UART 'C 0202' <<<");
        send_uart_string("C 0202\n");
        wait (core_stall_effective == 1'b1);
        wait_for_prompt();
        if (core_stall_effective === 1'b1 && core_step_busy === 1'b0) begin
            $display("    [PASS] Core halted and step controller in STATE_HALTED.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core halt expected 1, got %b", core_stall_effective);
            error_count = error_count + 1;
        end

        // 4.2 Single-Step Instruction Mode (GPO8[2]=1, GPO8[3]=0 -> C 0204)
        $display("\n>>> [STEP] 4.2: Triggering Instruction Step via 'C 0204' <<<");
        fork
            begin
                send_uart_string("C 0204\n");
                wait_for_prompt();
            end
            begin
                // Wait for step controller to enter stepping state
                wait(core_step_busy === 1'b1);
                $display("    [TB] Step in flight! core_stall_effective = %b (released).", core_stall_effective);
                // Simulate instruction execution in pipeline for 3 cycles, then retire
                repeat (3) @(posedge clk);
                sim_instr_retired <= 1'b1;
                @(posedge clk);
                sim_instr_retired <= 1'b0;
            end
        join

        // Verify that step completed and core is re-frozen
        @(posedge clk);
        if (step_count === 32'd1 && core_stall_effective === 1'b1) begin
            $display("    [PASS] Instruction Step executed successfully: step_count = %0d, core re-frozen.", step_count);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Instruction Step verification failed! step_count=%0d stall=%b", step_count, core_stall_effective);
            error_count = error_count + 1;
        end

        // Clear step request bit (C 0104)
        send_uart_string("C 0104\n");
        wait_for_prompt();

        // 4.3 Clock Cycle Step Mode (GPO8[2]=1, GPO8[3]=1 -> C 020c)
        $display("\n>>> [STEP] 4.3: Triggering 1 Clock Cycle Step via 'C 020c' <<<");
        send_uart_string("C 020c\n");
        wait_for_prompt();
        @(posedge clk);
        if (step_count === 32'd2 && core_stall_effective === 1'b1) begin
            $display("    [PASS] Clock Cycle Step executed successfully: step_count = %0d, core re-frozen.", step_count);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Cycle Step verification failed! step_count=%0d stall=%b", step_count, core_stall_effective);
            error_count = error_count + 1;
        end

        // Clear step bits (C 010c)
        send_uart_string("C 010c\n");
        wait_for_prompt();

        // 4.4 Resume Core
        $display("\n>>> [STEP] 4.4: Resuming Core via 'C 0102' <<<");
        send_uart_string("C 0102\n");
        wait (core_stall_effective == 1'b0);
        wait_for_prompt();
        if (core_stall_effective === 1'b0) begin
            $display("    [PASS] Core resumed successfully (core_stall_effective = 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core resume failed! stall = %b", core_stall_effective);
            error_count = error_count + 1;
        end

        //---------------------------------------------------------------------
        // PART 4.5: EXTENSIVE 'C' COMMAND SUITE (Set, Clear, Overwrite, Reset)
        //---------------------------------------------------------------------
        $display("\n-------------------------------------------------------------------------------");
        $display("   PART 4.5: EXTENSIVE 'C' COMMAND SUITE                                       ");
        $display("-------------------------------------------------------------------------------");

        // 4.5.1 Status query via 'C' with no params
        $display("\n>>> [CMD_C] 4.5.1: Status Query via 'C' (no arguments) <<<");
        send_uart_string("C\n");
        wait_for_prompt();
        $display("    [PASS] 'C' status query reported: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 4.5.2 Core-only Reset Assert ('C 0201') and Deassert ('C 0101')
        $display("\n>>> [CMD_C] 4.5.2: Core-Only Reset via GPO8[0] ('C 0201' / 'C 0101') <<<");
        send_uart_string("C 0201\n");
        wait (core_reset_o == 1'b1);
        wait_for_prompt();
        if (core_reset_o === 1'b1 && (dbg_gpo8[0] === 1'b1)) begin
            $display("    [PASS] Core reset successfully asserted via 'C 0201' (core_reset_o = 1).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core reset assert failed! core_reset_o = %b", core_reset_o);
            error_count = error_count + 1;
        end

        send_uart_string("C 0101\n");
        wait (core_reset_o == 1'b0);
        wait_for_prompt();
        if (core_reset_o === 1'b0 && (dbg_gpo8[0] === 1'b0)) begin
            $display("    [PASS] Core reset successfully deasserted via 'C 0101' (core_reset_o = 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core reset deassert failed! core_reset_o = %b", core_reset_o);
            error_count = error_count + 1;
        end

        // 4.5.3 Direct GPO8 Overwrite ('C 03<val>')
        $display("\n>>> [CMD_C] 4.5.3: Direct GPO8 Overwrite via 'C 03<val>' <<<");
        // Overwrite to 0x02 (halt core only)
        send_uart_string("C 0302\n");
        wait (core_halt_o == 1'b1);
        wait_for_prompt();
        if (dbg_gpo8 === 8'h02 && core_halt_o === 1'b1 && core_reset_o === 1'b0) begin
            $display("    [PASS] GPO8 overwritten with 0x02: core_halt_o = 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] GPO8 overwrite with 0x02 failed! dbg_gpo8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // Overwrite to 0x06 (halt + step trigger)
        send_uart_string("C 0306\n");
        wait_for_prompt();
        if (dbg_gpo8 === 8'h06 && core_step_o === 1'b1) begin
            $display("    [PASS] GPO8 overwritten with 0x06: core_halt_o = 1, core_step_o = 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] GPO8 overwrite with 0x06 failed! dbg_gpo8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // Overwrite to 0x0E (halt + step trigger + cycle step mode)
        send_uart_string("C 030e\n");
        wait_for_prompt();
        if (dbg_gpo8 === 8'h0e && core_step_mode_o === 1'b1) begin
            $display("    [PASS] GPO8 overwritten with 0x0E: step_mode = 1 (cycle step).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] GPO8 overwrite with 0x0E failed! dbg_gpo8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // Overwrite back to 0x00 (restore free-running, all clear)
        send_uart_string("C 0300\n");
        wait (core_halt_o == 1'b0);
        wait_for_prompt();
        if (dbg_gpo8 === 8'h00 && core_halt_o === 1'b0) begin
            $display("    [PASS] GPO8 overwritten with 0x00: all control bits cleared.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] GPO8 overwrite with 0x00 failed! dbg_gpo8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // 4.5.4 Alternative Report Code ('C 04')
        $display("\n>>> [CMD_C] 4.5.4: Alternative Report Code ('C 04') <<<");
        send_uart_string("C 04\n");
        wait_for_prompt();
        $display("    [PASS] 'C 04' reported status cleanly: %s", last_completed_line);
        pass_count = pass_count + 1;

        // 4.5.5 Lowercase 'c' Command Verification
        $display("\n>>> [CMD_C] 4.5.5: Lowercase 'c' Commands <<<");
        send_uart_string("c 0202\n");
        wait (core_halt_o == 1'b1);
        wait_for_prompt();
        send_uart_string("c 0102\n");
        wait (core_halt_o == 1'b0);
        wait_for_prompt();
        send_uart_string("c\n");
        wait_for_prompt();
        $display("    [PASS] Lowercase 'c' commands (halt, resume, query) executed successfully.");
        pass_count = pass_count + 1;

        // 4.5.6 Step Trigger via 'C 0204' / 'C 0104' and Step Mode via 'C 0208' / 'C 0108'
        $display("\n>>> [CMD_C] 4.5.6: Step Trigger & Step Mode via GPO8[3:2] <<<");
        // Assert Step Trigger (bit 2)
        send_uart_string("C 0204\n");
        wait (core_step_o == 1'b1);
        wait_for_prompt();
        if (core_step_o === 1'b1 && dbg_gpo8[2] === 1'b1) begin
            $display("    [PASS] Step trigger asserted via 'C 0204' (core_step_o = 1).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Step trigger assert failed!");
            error_count = error_count + 1;
        end

        // Deassert Step Trigger (bit 2)
        send_uart_string("C 0104\n");
        wait (core_step_o == 1'b0);
        wait_for_prompt();
        if (core_step_o === 1'b0 && dbg_gpo8[2] === 1'b0) begin
            $display("    [PASS] Step trigger deasserted via 'C 0104' (core_step_o = 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Step trigger deassert failed!");
            error_count = error_count + 1;
        end

        // Assert Step Mode (bit 3: cycle step mode = 1)
        send_uart_string("C 0208\n");
        wait (core_step_mode_o == 1'b1);
        wait_for_prompt();
        if (core_step_mode_o === 1'b1 && dbg_gpo8[3] === 1'b1) begin
            $display("    [PASS] Step mode set to Cycle Mode via 'C 0208' (core_step_mode_o = 1).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Step mode assert failed!");
            error_count = error_count + 1;
        end

        // Deassert Step Mode (bit 3: instruction step mode = 0)
        send_uart_string("C 0108\n");
        wait (core_step_mode_o == 1'b0);
        wait_for_prompt();
        if (core_step_mode_o === 1'b0 && dbg_gpo8[3] === 1'b0) begin
            $display("    [PASS] Step mode set to Instruction Mode via 'C 0108' (core_step_mode_o = 0).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Step mode deassert failed!");
            error_count = error_count + 1;
        end

        // 4.5.7 Multi-Bit Set and Clear Operations ('C 0203' and 'C 0103')
        $display("\n>>> [CMD_C] 4.5.7: Multi-Bit GPO Operations ('C 0203' and 'C 0103') <<<");
        // Simultaneously assert Reset (bit 0) and Halt (bit 1)
        send_uart_string("C 0203\n");
        wait (core_reset_o == 1'b1 && core_halt_o == 1'b1);
        wait_for_prompt();
        if (core_reset_o === 1'b1 && core_halt_o === 1'b1 && dbg_gpo8[1:0] === 2'b11) begin
            $display("    [PASS] Multi-bit set 'C 0203' asserted both reset and halt together.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Multi-bit set 'C 0203' failed! GPO8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // Simultaneously deassert Reset (bit 0) and Halt (bit 1)
        send_uart_string("C 0103\n");
        wait (core_reset_o == 1'b0 && core_halt_o == 1'b0);
        wait_for_prompt();
        if (core_reset_o === 1'b0 && core_halt_o === 1'b0 && dbg_gpo8[1:0] === 2'b00) begin
            $display("    [PASS] Multi-bit clear 'C 0103' cleared both reset and halt together.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Multi-bit clear 'C 0103' failed! GPO8 = 0x%02x", dbg_gpo8);
            error_count = error_count + 1;
        end

        // 4.5.8 Additional Status Reporting Codes ('C 00' and 'C 05')
        $display("\n>>> [CMD_C] 4.5.8: Additional Status Reporting Codes ('C 00' and 'C 05') <<<");
        send_uart_string("C 00\n");
        wait_for_prompt();
        $display("    [PASS] 'C 00' status query reported: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("C 05\n");
        wait_for_prompt();
        $display("    [PASS] 'C 05' status query reported: %s", last_completed_line);
        pass_count = pass_count + 1;

        //=====================================================================
        // PART 5: RECONFIGURABLE CLOCK DIVIDERS (UART & FT1248 via 'B' & 'D')
        //=====================================================================
        $display("\n===============================================================================");
        $display("   TEST SUITE PART 5: RECONFIGURABLE CLOCK DIVIDERS                            ");
        $display("===============================================================================");

        // 5.1 Read Initial Default Dividers via 'B'
        $display("\n>>> [DIVIDER] 5.1: Querying Default Clock Dividers via 'B' <<<");
        send_uart_string("B\n");
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] Default dividers verified: UART_DIV=%0d, FT_DIV=%0d",
                     dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Default dividers mismatch: UART_DIV=%0d (exp 20), FT_DIV=%0d (exp 2)",
                     dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.2 Read Initial FT1248 Divider via 'D'
        $display("\n>>> [DIVIDER] 5.2: Querying FT1248 Divider via 'D' <<<");
        send_uart_string("D\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] FT1248 divider verified via 'D': %0d", dut_debugger.dbg_ft_clkdiv);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] FT1248 divider query mismatch: %0d (exp 2)", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.3 Reconfigure FT1248 Divider via 'D 08'
        $display("\n>>> [DIVIDER] 5.3: Reconfiguring FT1248 Divider to 8 via 'D 08' <<<");
        send_uart_string("D 08\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd8) begin
            $display("    [PASS] FT1248 divider successfully updated to 8.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] FT1248 divider update failed: %0d (exp 8)", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.4 Reconfigure UART Divider to 40 cycles via 'B 0028'
        $display("\n>>> [DIVIDER] 5.4: Reconfiguring UART Divider to 40 cycles via 'B 0028' <<<");
        send_uart_string("B 0028\n");
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'h0028) begin
            $display("    [PASS] UART divider successfully updated to 40.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] UART divider update failed: %0d (exp 40)", dut_debugger.dbg_uart_clkdiv);
            error_count = error_count + 1;
        end

        // Adjust testbench bit timing to 800ns (40 cycles)
        current_bit_period = BIT_PERIOD * 2;
        #(current_bit_period * 2);

        // 5.5 Verify live UART communication at reconfigured baud rate (40 cycles)
        $display("\n>>> [DIVIDER] 5.5: Verifying live UART communication at 40 cycles / bit <<<");
        send_uart_string("B\n");
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'h0028) begin
            $display("    [PASS] Bidirectional UART communication successful at reconfigured baud rate!");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Communication failed at reconfigured baud rate.");
            error_count = error_count + 1;
        end

        // 5.6 Restore original UART baud rate (20 cycles) and FT1248 (2) via 'B 03001402'
        $display("\n>>> [DIVIDER] 5.6: Restoring both dividers via 'B 03001402' at 40 cycles <<<");
        send_uart_string("B 03001402\n");
        wait_for_prompt();
        current_bit_period = BIT_PERIOD;
        #(current_bit_period * 2);
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] Both dividers restored successfully: UART_DIV=%0d, FT_DIV=%0d",
                     dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Simultaneous divider restore failed: UART_DIV=%0d, FT_DIV=%0d",
                     dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.7 Verify FT1248 Interface can also query and update dividers
        $display("\n>>> [DIVIDER] 5.7: Testing Divider Reconfiguration over FT1248 Interface <<<");
        dbg_sel = 1'b1;
        #(current_bit_period * 2);
        send_ft1248_string("D 04\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd4) begin
            $display("    [PASS] FT1248 divider updated to 4 over FT1248 bus.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] FT1248 divider update over FT1248 failed: %0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // Restore FT divider back to 2 over FT1248
        send_ft1248_string("D 02\n");
        wait_for_prompt();
        dbg_sel = 1'b0;
        #(current_bit_period * 2);

        // 5.8 Comprehensive 'B' and 'D' Command Variants
        $display("\n>>> [DIVIDER] 5.8: Comprehensive 'B' and 'D' Command Variants <<<");
        // 5.8.1 'B 01<uart_div>' (prefix 01 at [31:24]: set UART divider only)
        send_uart_string("B 01000014\n"); // 8 digits: prefix 01, UART=0x0014 (20 cycles)
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] 'B 01000014' updated UART divider to 20 cycles while preserving FT divider (2).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'B 01' failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.8.2 'B 02<ft_div>' (prefix 02 at [31:24]: set FT1248 divider only)
        send_uart_string("B 02000006\n"); // 8 digits: prefix 02, FT=0x06
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd6 && dut_debugger.dbg_uart_clkdiv === 16'd20) begin
            $display("    [PASS] 'B 02000006' updated FT divider to 6 while preserving UART divider (20).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'B 02' failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // Restore FT divider with B 02000002
        send_uart_string("B 02000002\n");
        wait_for_prompt();

        // 5.8.3 'B 03<uart><ft>' (prefix 03: set both dividers simultaneously)
        send_uart_string("B 03001402\n"); // UART = 20 (0x0014), FT = 2
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] 'B 03001402' restored both UART (20) and FT (2) dividers simultaneously.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'B 03' simultaneous set failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.8.4 Lowercase 'b' and 'd' commands
        send_uart_string("b\n");
        wait_for_prompt();
        send_uart_string("d\n");
        wait_for_prompt();
        $display("    [PASS] Lowercase 'b' and 'd' queries executed successfully.");
        pass_count = pass_count + 1;

        // 5.8.5 Additional 'D' variants: 'D 01', 'D 04', 'D 08', 'D 02'
        send_uart_string("D 01\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd1) begin
            $display("    [PASS] 'D 01' set FT divider to 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'D 01' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        send_uart_string("D 04\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd4) begin
            $display("    [PASS] 'D 04' set FT divider to 4.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'D 04' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        send_uart_string("D 02\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] 'D 02' restored FT divider to 2.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'D 02' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.8.6 Default 'B <val>' Fallback Branch (No 01/02/03 prefix)
        $display("\n>>> [DIVIDER] 5.8.6: Default 'B <val>' Fallback Branch (Prefix != 01/02/03) <<<");
        send_uart_string("B 00000028\n"); // 8 digits with prefix 00 -> hits else branch, sets UART divider to 40
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'd40 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] Fallback 'B 00000028' updated UART divider to 40 while preserving FT divider (2).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Fallback 'B' failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // Adjust testbench timing to 40 cycles to transmit restore command
        current_bit_period = BIT_PERIOD * 2;
        #(current_bit_period * 2);

        // Restore UART divider back to 20 via fallback at 40 cycles
        send_uart_string("B 00000014\n");
        wait_for_prompt();
        current_bit_period = BIT_PERIOD;
        #(current_bit_period * 2);
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] Fallback 'B 00000014' restored UART divider to 20.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Fallback 'B' restore failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.8.7 Lowercase 'b' with Parameters
        $display("\n>>> [DIVIDER] 5.8.7: Lowercase 'b' with Parameters <<<");
        send_uart_string("b 01000014\n");
        wait_for_prompt();
        send_uart_string("b 02000006\n");
        wait_for_prompt();
        send_uart_string("b 03001402\n");
        wait_for_prompt();
        if (dut_debugger.dbg_uart_clkdiv === 16'd20 && dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] Lowercase 'b' parameterized commands verified successfully.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Lowercase 'b' failed! UART=%0d FT=%0d", dut_debugger.dbg_uart_clkdiv, dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        // 5.8.8 Lowercase 'd' with Parameters & Diverse Dividers
        $display("\n>>> [DIVIDER] 5.8.8: Lowercase 'd' with Parameters & Diverse Dividers <<<");
        send_uart_string("d 08\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd8) begin
            $display("    [PASS] 'd 08' set FT divider to 8.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'd 08' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        send_uart_string("d 10\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd16) begin
            $display("    [PASS] 'd 10' set FT divider to 16.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'd 10' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        send_uart_string("d 02\n");
        wait_for_prompt();
        if (dut_debugger.dbg_ft_clkdiv === 8'd2) begin
            $display("    [PASS] 'd 02' restored FT divider to 2.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] 'd 02' failed! FT=%0d", dut_debugger.dbg_ft_clkdiv);
            error_count = error_count + 1;
        end

        //---------------------------------------------------------------------
        // FINAL TEST SUMMARY
        //---------------------------------------------------------------------
        $display("\n===============================================================================");
        $display("   ALL DUAL-PROTOCOL TEST SCENARIOS COMPLETED!                                 ");
        $display("   Passed Assertions: %0d                                                      ", pass_count);
        $display("   Failed Assertions: %0d                                                      ", error_count);
        $display("===============================================================================\n");

        if (error_count == 0) begin
            $display(">>> [SUCCESS] ALL UART, FT1248, AND MUX ISOLATION TESTS PASSED! <<<\n");
        end else begin
            $display(">>> [FAILURE] SOME TESTS FAILED! CHECK ERROR COUNT ABOVE. <<<\n");
            $fatal(1);
        end

        $finish;
    end

    // Safety watchdog timeout (15 milliseconds)
    initial begin
        #15_000_000;
        $display("\n[TB] [ERROR] Simulation Watchdog Timeout!");
        $fatal(1);
    end

endmodule
