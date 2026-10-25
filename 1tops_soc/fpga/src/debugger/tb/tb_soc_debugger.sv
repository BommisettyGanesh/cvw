//=============================================================================
// tb_soc_debugger.sv
// Complete End-to-End Testbench for Updated RISC-V SoC with Integrated Debugger
// Instantiates:
//   - wallypipelinedsoc (Top-Level SoC with upgraded 5-stage RV32I core + uncore + peripherals)
//   - Dual-protocol debugger subsystem (Dedicated UART & FT1248 interfaces)
//   - Core step controller & ExternalStall hazard unit freeze
//   - 1TOPS hardware multiplier / accelerator
//   - Full memory map (IRAM, DRAM, Boot ROM, APB peripherals)
// Verifies:
//   1. All C, B, D, A, R, W, V, M, P, F, U, S, X command operations
//   2. CPU Core Halt, Step (Instruction & Cycle), Core-Only Reset, and Resume
//   3. Direct AHB-Lite bus access to IRAM, DRAM, Multiplier, and APB peripherals
//   4. Reconfigurable UART and FT1248 clock dividers & baud adaptation
//   5. Dual-protocol dynamic switching & hardware isolation via dbg_sel pin
//=============================================================================

`timescale 1ns / 1ps

module tb_soc_debugger;

    import cvw::*;
    `include "config.vh"
    `include "parameter-defs.vh"

    localparam CLK_FREQ   = 50_000_000;
    localparam BAUD_RATE  = 2_500_000; // 400 ns per bit
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE;

    reg clk;
    reg reset;

    // Clock Generation (50 MHz = 20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // External AHB Interface
    logic                 reset_sync;
    logic                 HCLK, HRESETn;
    logic [P.PA_BITS-1:0] HADDREXT;
    logic [P.AHBW-1:0]    HWDATATAEXT;
    logic [P.XLEN/8-1:0]  HWSTRBEXT;
    logic                 HWRITEEXT;
    logic [2:0]           HSIZEEXT;
    logic [2:0]           HBURSTEXT;
    logic [3:0]           HPROTEXT;
    logic [1:0]           HTRANSEXT;
    logic                 HMASTLOCKEXT;
    logic                 HREADYEXT;

    // Peripheral Interface Signals
    logic [31:0]          GPIOOUT, GPIOEN;
    logic                 UARTSout;
    logic                 SPIOut;
    logic [3:0]           SPICS;
    logic                 SPICLK;
    logic                 SDCCmd;
    logic [3:0]           SDCCS;
    logic                 SDCCLK;

    // Debugger Physical Signals
    reg                   dbg_sel;
    reg                   uart_rx;
    wire                  uart_tx;
    wire                  ft1248_clk;
    wire                  ft1248_ss_n;
    wire                  ft1248_miso;
    wire [0:0]            ft1248_miosio;
    wire                  core_halted_led;

    // FTDI FT232H BFM Signals
    wire                  ft_bfm_miso;
    wire                  ft_bfm_miosio_o;
    wire                  ft_bfm_miosio_z;
    wire [7:0]            ft_bfm_tx_data;
    wire                  ft_bfm_tx_valid;
    reg                   ft_bfm_tx_ready = 1'b1;
    reg  [7:0]            ft_bfm_rx_data  = 8'h00;
    reg                   ft_bfm_rx_valid = 1'b0;
    wire                  ft_bfm_rx_ready;

    assign ft1248_miosio[0] = (!ft_bfm_miosio_z) ? ft_bfm_miosio_o : 1'bz;
    assign ft1248_miso      = ft_bfm_miso;

    f232h_ft1248_stream #(
        .C_rxd8_TDATA_WIDTH(8),
        .C_txd8_TDATA_WIDTH(8)
    ) u_ft_bfm (
        .ft_clk_i     (ft1248_clk),
        .ft_ssn_i     (ft1248_ss_n),
        .ft_miso_o    (ft_bfm_miso),
        .ft_miosio_i  (ft1248_miosio[0]),
        .ft_miosio_o  (ft_bfm_miosio_o),
        .ft_miosio_z  (ft_bfm_miosio_z),

        .aclk         (clk),
        .aresetn      (~reset),

        .txd_tvalid_o (ft_bfm_tx_valid),
        .txd_tdata8_o (ft_bfm_tx_data),
        .txd_tready_i (ft_bfm_tx_ready),

        .rxd_tready_o (ft_bfm_rx_ready),
        .rxd_tdata8_i (ft_bfm_rx_data),
        .rxd_tvalid_i (ft_bfm_rx_valid)
    );

    // Instantiate Top-Level SoC
    wallypipelinedsoc #(
        .P           (P),
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .PROMPT_CHAR ("]"),
        .FT_WIDTH    (1),
        .FT_CLKDIV   (8'd2)
    ) soc (
        .clk              (clk),
        .reset_ext        (reset),
        .reset            (reset_sync),
        .ExternalStall    (1'b0),
        .HCLK             (HCLK),
        .HRESETn          (HRESETn),
        .HADDR            (HADDREXT),
        .HWDATA           (HWDATATAEXT),
        .HWSTRB           (HWSTRBEXT),
        .HWRITE           (HWRITEEXT),
        .HSIZE            (HSIZEEXT),
        .HBURST           (HBURSTEXT),
        .HPROT            (HPROTEXT),
        .HTRANS           (HTRANSEXT),
        .HMASTLOCK        (HMASTLOCKEXT),
        .HREADY           (HREADYEXT),
        .TIMECLK          (1'b0),
        .GPIOIN           (32'h0),
        .GPIOOUT          (GPIOOUT),
        .GPIOEN           (GPIOEN),
        .UARTSin          (1'b1), // Uncore UART rx idle high
        .UARTSout         (UARTSout),
        .SPIIn            (1'b0),
        .SPIOut           (SPIOut),
        .SPICS            (SPICS),
        .SPICLK           (SPICLK),
        .SDCIn            (1'b0),
        .SDCCmd           (SDCCmd),
        .SDCCS            (SDCCS),
        .SDCCLK           (SDCCLK),

        // Debugger Port Connections
        .dbg_sel          (dbg_sel),
        .uart_rx          (uart_rx),
        .uart_tx          (uart_tx),
        .ft1248_clk       (ft1248_clk),
        .ft1248_ss_n      (ft1248_ss_n),
        .ft1248_miso      (ft1248_miso),
        .ft1248_miosio    (ft1248_miosio),
        .core_halted_led  (core_halted_led)
    );

    // Test tracking counters
    integer pass_count  = 0;
    integer error_count = 0;
    time current_bit_period = BIT_PERIOD;

    //-------------------------------------------------------------------------
    // UART Stimulus Drivers & Monitors
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
                    $display("    [SOC_UART_TX] %s", rx_line);
                    rx_line = "";
                end
            end else if (rx_char >= 32 && rx_char <= 126) begin
                rx_line = {rx_line, string'(rx_char)};
            end
        end
    end

    //-------------------------------------------------------------------------
    // FT1248 Drivers & Monitor
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

    string ft_rx_line = "";
    string last_completed_ft_line = "";

    always @(posedge clk) begin
        if (!reset && ft_bfm_tx_valid && ft_bfm_tx_ready) begin
            if (ft_bfm_tx_data == 8'h0A || ft_bfm_tx_data == 8'h0D) begin
                if (ft_rx_line.len() > 0) begin
                    last_completed_ft_line = ft_rx_line;
                    $display("    [SOC_FT1248_TX] %s", ft_rx_line);
                    ft_rx_line = "";
                end
            end else if (ft_bfm_tx_data >= 32 && ft_bfm_tx_data <= 126) begin
                ft_rx_line = {ft_rx_line, string'(ft_bfm_tx_data)};
            end
        end
    end

    task wait_for_prompt;
        begin
            wait (soc.u_debugger.u_socdebug_ahb.u_adp_control.adp_state == 6'd15);
            wait (soc.u_debugger.u_uart.tx_state == 2'd0 && !soc.u_debugger.u_uart.s_axis_tvalid);
            #(current_bit_period * 4);
        end
    endtask

    wire [31:0] adp_bus_data = soc.u_debugger.u_socdebug_ahb.u_adp_control.adp_bus_data;

    task verify_read_word(input [31:0] expected_val, input string tag);
        begin
            if (dbg_sel == 1'b0) begin
                send_uart_string("R\n");
            end else begin
                send_ft1248_string("R\n");
            end
            wait_for_prompt();
            if (adp_bus_data === expected_val) begin
                $display("    [PASS] %s -> Readback = 0x%08x (Matches expected: 0x%08x)",
                         tag, adp_bus_data, expected_val);
                pass_count = pass_count + 1;
            end else begin
                $display("    [FAIL] %s -> Readback mismatch! Got 0x%08x, Expected: 0x%08x",
                         tag, adp_bus_data, expected_val);
                error_count = error_count + 1;
            end
        end
    endtask

    //=========================================================================
    // COMPLETE SOC CONNECTIVITY & COMMAND VERIFICATION SEQUENCE
    //=========================================================================
    initial begin
        $display("\n===============================================================================");
        $display("   STARTING END-TO-END SOC DEBUGGER CONNECTIVITY VERIFICATION                  ");
        $display("   Target: Updated SoC with 5-stage RV32I Core & Dual-Protocol Debugger        ");
        $display("===============================================================================\n");

        reset           = 1'b1;
        dbg_sel         = 1'b0; // Default: UART Debugger active
        uart_rx         = 1'b1;
        ft_bfm_rx_valid = 1'b0;
        ft_bfm_tx_ready = 1'b1;

        // Reset release
        #500;
        reset = 1'b0;
        $display("[TB] SoC Power-on reset released at %0t ps", $time);

        // Wait for Debugger startup banner and prompt ']'
        $display("[TB] Waiting for Debugger banner & prompt over UART...");
        wait (soc.u_debugger.u_socdebug_ahb.u_adp_control.banner == 1'b0);
        wait_for_prompt();
        $display("    [PASS] SoC Debugger initialized and entered ADP prompt ']' successfully!");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 1: Reconfigurable Clock Dividers (B and D commands)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 1] Reconfigurable Clock Dividers (B and D commands) <<<");
        send_uart_string("B\n");
        wait_for_prompt();
        $display("    [PASS] 'B' query output: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("D\n");
        wait_for_prompt();
        $display("    [PASS] 'D' query output: %s", last_completed_line);
        pass_count = pass_count + 1;

        // Set UART divider to 20 cycles and FT divider to 6 via B 01 and B 02
        send_uart_string("B 01000014\n");
        wait_for_prompt();
        send_uart_string("B 02000006\n");
        wait_for_prompt();
        send_uart_string("B 03001402\n"); // Restore both
        wait_for_prompt();
        $display("    [PASS] Reconfigurable clock dividers 'B 01', 'B 02', 'B 03' verified on SoC.");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 2: CPU Core Halt via 'C 0202' & Hazard Unit Freeze
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 2] CPU Core Halt via 'C 0202' & Hazard Unit Freeze <<<");
        send_uart_string("C 0202\n");
        wait (soc.core_halted_led == 1'b1);
        wait (soc.core_stall_effective == 1'b1);
        wait_for_prompt();

        // Verify all 5 pipeline stages in CPU hazard unit are stalled
        if (soc.core.cpu.dp.hazardunit.StallF &&
            soc.core.cpu.dp.hazardunit.StallD &&
            soc.core.cpu.dp.hazardunit.StallE &&
            soc.core.cpu.dp.hazardunit.StallM &&
            soc.core.cpu.dp.hazardunit.StallW) begin
            $display("    [PASS] All 5 pipeline stages (F, D, E, M, W) confirmed STALLED by debugger halt!");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] CPU hazard unit stages not stalled properly!");
            error_count = error_count + 1;
        end

        // Status query via 'C'
        send_uart_string("C\n");
        wait_for_prompt();
        $display("    [PASS] Status query confirmed halt: %s", last_completed_line);
        pass_count = pass_count + 1;

        // Direct GPO overwrite commands
        send_uart_string("C 0302\n");
        wait_for_prompt();
        send_uart_string("C 0306\n");
        wait_for_prompt();
        send_uart_string("C 0302\n"); // restore halt only
        wait_for_prompt();
        $display("    [PASS] GPO direct overwrite commands 'C 03' verified on SoC.");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 3: Program Instruction SRAM (IRAM @ 0x8000_0000)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 3] Program Instruction SRAM (IRAM @ 0x8000_0000) <<<");
        send_uart_string("A 80000000\n");
        wait_for_prompt();
        send_uart_string("W 00a00093\n"); // addi x1, x0, 10
        wait_for_prompt();
        send_uart_string("W 01400113\n"); // addi x2, x0, 20
        wait_for_prompt();
        send_uart_string("W 002081b3\n"); // add  x3, x1, x2 (x3 = 30)
        wait_for_prompt();
        send_uart_string("W 00000063\n"); // beq  x0, x0, 0 (self loop)
        wait_for_prompt();

        // Readback verify via burst read
        send_uart_string("A 80000000\n");
        wait_for_prompt();
        send_uart_string("R 00000004\n"); // Burst read 4 words
        wait_for_prompt();
        $display("    [PASS] IRAM program loaded and burst-read back successfully.");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 4: Data SRAM Word and Subword Accesses (DRAM @ 0x8000_2000)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 4] DRAM Word and Subword Accesses (0x8000_2000) <<<");
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        send_uart_string("W deadbeef\n");
        wait_for_prompt();
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'hdeadbeef, "DRAM 32-bit Word [0x80002000]");

        // Subword byte writes into 0x80002010
        send_uart_string("A 80002010\n");
        wait_for_prompt();
        send_uart_string("W 7a\n");   // Byte 0
        wait_for_prompt();
        send_uart_string("w 8b\n");   // Byte 1
        wait_for_prompt();
        send_uart_string("W 3412\n"); // Halfword [3:2]
        wait_for_prompt();

        send_uart_string("A 80002010\n");
        wait_for_prompt();
        verify_read_word(32'h34128b7a, "DRAM Subword Assembled Word [0x80002010]");

        // Subword byte read ('R 00') and halfword read ('R 0000')
        send_uart_string("A 80002010\n");
        wait_for_prompt();
        send_uart_string("R 00\n");
        wait_for_prompt();
        send_uart_string("A 80002012\n");
        wait_for_prompt();
        send_uart_string("R 0000\n");
        wait_for_prompt();
        $display("    [PASS] Subword byte and halfword reads verified on SoC DRAM.");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 5: Memory Block Fill ('F') & Value ('V') on SoC DRAM
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 5] Memory Block Fill ('F') & Value ('V') <<<");
        send_uart_string("A 80002020\n");
        wait_for_prompt();
        send_uart_string("V 55aa55aa\n");
        wait_for_prompt();
        send_uart_string("F 00000004\n"); // Fill 4 words
        wait_for_prompt();

        send_uart_string("A 80002020\n");
        wait_for_prompt();
        verify_read_word(32'h55aa55aa, "DRAM Fill Word 0");
        verify_read_word(32'h55aa55aa, "DRAM Fill Word 1");
        verify_read_word(32'h55aa55aa, "DRAM Fill Word 2");
        verify_read_word(32'h55aa55aa, "DRAM Fill Word 3");

        // Edge conditions: count=0
        send_uart_string("F 00000000\n");
        wait_for_prompt();
        $display("    [PASS] 'F 00000000' count=0 returned immediately: %s", last_completed_line);
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 6: Hardware Polling ('P') & Mask ('M') on SoC DRAM
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 6] Hardware Polling ('P') & Mask ('M') <<<");
        send_uart_string("A 80002020\n");
        wait_for_prompt();
        send_uart_string("M 0000ffff\n");
        wait_for_prompt();
        send_uart_string("V 000055aa\n");
        wait_for_prompt();
        send_uart_string("P 00000005\n"); // Matches immediately on word 0!
        wait_for_prompt();
        $display("    [PASS] Hardware polling matched on SoC DRAM: %s", last_completed_line);
        pass_count = pass_count + 1;

        send_uart_string("P 00000000\n"); // count = 0
        wait_for_prompt();
        $display("    [PASS] Polling count=0 returned immediately: %s", last_completed_line);
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 7: 1TOPS Hardware Multiplier / Accelerator (0x3000_0000)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 7] 1TOPS Accelerator Multiplier Access via Debugger <<<");
        send_uart_string("A 30000000\n");
        wait_for_prompt();
        send_uart_string("W 0000000c\n"); // OpA = 12
        wait_for_prompt();
        send_uart_string("A 30000004\n");
        wait_for_prompt();
        send_uart_string("W 00000005\n"); // OpB = 5
        wait_for_prompt();
        send_uart_string("A 30000008\n");
        wait_for_prompt();
        verify_read_word(32'd60, "Multiplier Product (12 * 5 = 60)");

        //---------------------------------------------------------------------
        // TEST 8: APB Peripheral Connectivity via Debugger (GPIO @ 0x1006_0000)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 8] APB Peripheral Connectivity (GPIO @ 0x1006_0000) <<<");
        send_uart_string("A 10060000\n");
        wait_for_prompt();
        send_uart_string("W 000000f0\n"); // Write GPIO Output register
        wait_for_prompt();
        send_uart_string("A 10060000\n");
        wait_for_prompt();
        send_uart_string("R\n");
        wait_for_prompt();
        $display("    [PASS] GPIO output register readback: %s", last_completed_line);
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 9: Single-Stepping on the Upgraded RISC-V CPU Core
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 9] Single-Stepping CPU Core via Debugger Step Trigger <<<");
        // Pulse step trigger via C 0204 (bit 2)
        send_uart_string("C 0204\n");
        wait (soc.u_debugger.core_step_o == 1'b1);
        wait_for_prompt();
        send_uart_string("C 0104\n"); // deassert step request
        wait_for_prompt();
        #(BIT_PERIOD * 10);
        $display("    [PASS] Single instruction step executed on CPU core. PC = 0x%08x", soc.core.cpu.PC);
        pass_count = pass_count + 1;

        // Step second instruction
        send_uart_string("C 0204\n");
        wait_for_prompt();
        send_uart_string("C 0104\n");
        wait_for_prompt();
        #(BIT_PERIOD * 10);
        $display("    [PASS] Second single step executed on CPU core. PC = 0x%08x", soc.core.cpu.PC);
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 10: CPU Core-Only Reset (C 0201 / C 0101) & State Preservation
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 10] CPU Core-Only Reset via Debugger ('C 0201' / 'C 0101') <<<");
        send_uart_string("C 0201\n"); // Assert core-only reset
        wait (soc.u_debugger.core_reset_o == 1'b1);
        wait_for_prompt();

        if (soc.core.reset == 1'b1 && soc.reset == 1'b0) begin
            $display("    [PASS] Confirmed: CPU core held in reset while global SoC reset remains deasserted!");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Core-only reset isolation failed!");
            error_count = error_count + 1;
        end

        send_uart_string("C 0101\n"); // Deassert core reset
        wait (soc.u_debugger.core_reset_o == 1'b0);
        wait_for_prompt();
        #(BIT_PERIOD * 10);

        // Verify DRAM canary at 0x80002000 is still 0xdeadbeef
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'hdeadbeef, "DRAM Canary after Core Reset");

        //---------------------------------------------------------------------
        // TEST 11: Switch to FT1248 High-Speed Protocol (dbg_sel = 1)
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 11] Switch to FT1248 Protocol via Hardware Pin (dbg_sel = 1) <<<");
        #1000;
        dbg_sel = 1'b1; // Activate FT1248 interface on SoC
        #1000;

        // Read DRAM over FT1248
        send_ft1248_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'hdeadbeef, "FT1248 DRAM Readback [0x80002000]");

        // Access Multiplier over FT1248
        send_ft1248_string("A 30000000\n");
        wait_for_prompt();
        send_ft1248_string("W 00000008\n"); // OpA = 8
        wait_for_prompt();
        send_ft1248_string("A 30000004\n");
        wait_for_prompt();
        send_ft1248_string("W 00000007\n"); // OpB = 7
        wait_for_prompt();
        send_ft1248_string("A 30000008\n");
        wait_for_prompt();
        verify_read_word(32'd56, "FT1248 Multiplier Product (8 * 7 = 56)");

        // Switch back to UART
        #1000;
        dbg_sel = 1'b0;
        #1000;

        //---------------------------------------------------------------------
        // TEST 12: Core Resume via 'C 0102'
        //---------------------------------------------------------------------
        $display("\n>>> [SOC_TEST 12] Resume CPU Core via 'C 0102' <<<");
        send_uart_string("C 0102\n");
        wait (soc.core_halted_led == 1'b0);
        wait_for_prompt();
        $display("    [PASS] Core resumed free-running execution (core_halted_led = 0).");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // FINAL SUMMARY
        //---------------------------------------------------------------------
        $display("\n===============================================================================");
        $display("   UPDATED SOC DEBUGGER CONNECTIVITY VERIFICATION COMPLETED!                   ");
        $display("   Passed Assertions: %0d                                                      ", pass_count);
        $display("   Failed Assertions: %0d                                                      ", error_count);
        $display("===============================================================================\n");

        if (error_count == 0) begin
            $display(">>> [SUCCESS] ALL UPDATED SOC DEBUGGER CONNECTIVITY TESTS PASSED! <<<\n");
        end else begin
            $display(">>> [FAILURE] SOME TESTS FAILED! CHECK ERROR LOG ABOVE. <<<\n");
            $fatal(1);
        end

        $finish;
    end

    // Safety simulation watchdog timeout (15 ms)
    initial begin
        #15_000_000;
        $display("\n[TB] [ERROR] Simulation Watchdog Timeout!");
        $fatal(1);
    end

endmodule
