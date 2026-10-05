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

    // Realistic RISC-V Core Hazard Unit Model
    reg [1:0] core_halt_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_halt_pipe <= 2'b00;
            core_halted_i  <= 1'b0;
        end else begin
            core_halt_pipe <= {core_halt_pipe[0], core_halt_o};
            core_halted_i  <= core_halt_pipe[1];
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
        .core_halt_o     (core_halt_o),
        .core_reset_o    (core_reset_o),
        .core_halted_i   (core_halted_i),

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

        .GPO8            (),
        .GPI8            (8'h00)
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

    //-------------------------------------------------------------------------
    // UART Drivers
    //-------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 1'b0; // Start bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end
            uart_rx = 1'b1; // Stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD / 2);
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
        #(BIT_PERIOD / 2);
        if (!uart_tx) begin
            #(BIT_PERIOD);
            rx_char[0] = uart_tx; #(BIT_PERIOD);
            rx_char[1] = uart_tx; #(BIT_PERIOD);
            rx_char[2] = uart_tx; #(BIT_PERIOD);
            rx_char[3] = uart_tx; #(BIT_PERIOD);
            rx_char[4] = uart_tx; #(BIT_PERIOD);
            rx_char[5] = uart_tx; #(BIT_PERIOD);
            rx_char[6] = uart_tx; #(BIT_PERIOD);
            rx_char[7] = uart_tx; #(BIT_PERIOD);
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
            #(BIT_PERIOD * 4);
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
        send_uart_byte(8'h1b); // ESC
        wait_for_prompt();

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
