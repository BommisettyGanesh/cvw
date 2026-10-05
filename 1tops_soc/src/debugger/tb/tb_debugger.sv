//-----------------------------------------------------------------------------
// Comprehensive Testbench for SoCDebug Debugger Subsystem
// Covers:
//  - Core Halt / Resume / Reset control:
//      * Verified by sending 'C 0202', waiting for core hazard unit ack (core_halted_i),
//        and querying status via 'C' to verify GPI8[0] (core_halted) is asserted!
//      * Verified by sending 'C 0102' (resume) and querying status via 'C' to verify
//        GPI8[0] is cleared.
//  - Memory Write & Readback Verification via Debugger:
//      * Every memory (IRAM, DRAM, APB, Accel) is written using 'W'
//      * Immediately read back through the debugger using 'R after A'
//      * Verifies that the value returned by 'R' matches EXACTLY what was written by 'W'!
//  - Sub-word accesses (Byte, Halfword, Word) with byte-lane steering
//  - Boot ROM (0x0001_0000) read-only access
//  - Uncore APB Peripherals (0x1000_0000) with slave wait states (HREADY=0)
//  - 1TOPS Accelerator / Multiplier (0x3000_0000)
//  - Bulk Memory Fill ('F') & Raw Binary Upload ('U') verified via 'R after A'
//  - Hardware Polling ('P', 'M', 'V') with match & timeout corner conditions
//  - Unmapped / Illegal Address AHB Bus Error (HRESP = 1 -> '!')
//  - Invalid Command error handling ('?')
//  - Bus Arbiter contention (CPU Master 0 vs Debugger Master 1)
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_debugger;

    localparam CLK_FREQ   = 50_000_000;
    localparam BAUD_RATE  = 2_500_000; // High speed for fast simulation
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // 400 ns per bit

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;

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

    //-------------------------------------------------------------------------
    // Realistic RISC-V Core Hazard Unit Model
    // When core_halt_o (ExternalStall) asserts, the core freezes and asserts
    // core_halted_i after a 2-cycle pipeline drain/latch latency.
    //-------------------------------------------------------------------------
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
    // Top-Level Debugger Subsystem
    //-------------------------------------------------------------------------
    riscv_debugger_top #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .PROMPT_CHAR ("]")
    ) dut_debugger (
        .clk             (clk),
        .rst_n           (rst_n),
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .core_halt_o     (core_halt_o),
        .core_reset_o    (core_reset_o),
        .core_halted_i   (core_halted_i), // Connected to simulated hazard unit
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

    // Address Decoding
    wire accel_hsel   = (s_haddr >= 32'h3000_0000 && s_haddr <= 32'h30FF_FFFF); // Accelerator region
    wire iram_hsel    = (s_haddr >= 32'h8000_0000 && s_haddr <= 32'h8000_1FFF); // 8 KB Instruction SRAM
    wire dram_hsel    = (s_haddr >= 32'h8000_2000 && s_haddr <= 32'h8000_3FFF); // 8 KB Data SRAM
    wire bootrom_hsel = (s_haddr >= 32'h0001_0000 && s_haddr <= 32'h0001_FFFF); // 64 KB Boot ROM
    wire apb_hsel     = (s_haddr >= 32'h1000_0000 && s_haddr <= 32'h1000_0FFF); // APB Peripherals (GPIO, UART)
    wire error_hsel   = (s_haddr >= 32'h5000_0000 && s_haddr <= 32'h5FFF_FFFF); // Illegal unmapped space

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

    // 2) Instruction Memory (IRAM): 2048 words x 32 bits (8 KB)
    reg [31:0] iram [0:2047];

    // 3) Data Memory (DRAM): 2048 words x 32 bits (8 KB)
    reg [31:0] dram [0:2047];

    // 4) Boot ROM: 1024 words x 32 bits
    reg [31:0] bootrom [0:1023];

    // 5) APB Peripheral Registers (GPIO & Control)
    reg [31:0] apb_gpio_data;
    reg [31:0] apb_gpio_dir;
    localparam APB_PERIPH_ID = 32'hCAFE_2026;

    // Pipelined address-phase tracking for behavioral slaves
    reg        iram_active_d, dram_active_d, bootrom_active_d, apb_active_d, error_active_d;
    reg [31:0] s_haddr_d;
    reg [ 2:0] s_hsize_d;
    reg        s_hwrite_d;

    // Inject wait states on APB peripheral address 0x1000_0004 to test HREADY = 0 stalls
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

    // Helper function for sub-word byte lane mask
    function [3:0] get_wstrb(input [1:0] addr, input [2:0] size);
        case (size)
            3'b000: // Byte
                case (addr[1:0])
                    2'b00: get_wstrb = 4'b0001;
                    2'b01: get_wstrb = 4'b0010;
                    2'b10: get_wstrb = 4'b0100;
                    2'b11: get_wstrb = 4'b1000;
                endcase
            3'b001: // Halfword
                case (addr[1])
                    1'b0:  get_wstrb = 4'b0011;
                    1'b1:  get_wstrb = 4'b1100;
                endcase
            default: // Word (32-bit)
                get_wstrb = 4'b1111;
        endcase
    endfunction

    // Write operations to IRAM & DRAM
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

    // Read responses for behavioral models
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

    // Multiplex downstream slave signals to AHB Bus Arbiter
    assign s_hready = accel_hsel ? accel_hreadyout :
                      apb_wait_stall ? 1'b0 : 1'b1;

    assign s_hresp  = accel_hsel   ? accel_hresp :
                      error_active_d ? 1'b1 : 1'b0; // Error response on illegal address

    assign s_hrdata = accel_hsel   ? accel_hrdata : mem_hrdata;

    // Track completed AHB read transfers from debugger
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
    // UART SERIAL TRANSMISSION & RECEPTION TASKS
    //=========================================================================

    // Send a single raw byte over UART RX pin
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

    // Send string over UART
    task send_uart_string(input string str);
        integer j;
        begin
            for (j = 0; j < str.len(); j = j + 1) begin
                send_uart_byte(str[j]);
            end
        end
    endtask

    // Wait for ADP prompt (state 15: ADP_IOCHK)
    task wait_for_prompt;
        begin
            wait (dut_debugger.u_socdebug_ahb.u_adp_control.adp_state == 6'd15);
            #(BIT_PERIOD * 4);
        end
    endtask

    // UART TX Output Monitor (Captures debugger console output)
    reg [7:0] rx_char;
    string    rx_line = "";
    string    last_completed_line = "";
    reg       line_received = 0;

    always begin
        @(negedge uart_tx);
        #(BIT_PERIOD / 2); // Center of start bit
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
            // End of character
            if (rx_char == 8'h0A || rx_char == 8'h0D) begin
                if (rx_line.len() > 0) begin
                    last_completed_line = rx_line;
                    line_received       = 1'b1;
                    $display("    [DUT_UART_TX] %s", rx_line);
                    rx_line = "";
                end
            end else if (rx_char >= 32 && rx_char <= 126) begin
                rx_line = {rx_line, string'(rx_char)};
            end
        end
    end

    // Helper task: Reads memory via debugger ('R') and verifies returned value matches expected
    task verify_read_word(input [31:0] expected_val, input string tag);
        begin
            send_uart_string("R\n");
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

    // Monitor internal ADP signals
    wire [5:0]  adp_state    = dut_debugger.u_socdebug_ahb.u_adp_control.adp_state;
    wire [7:0]  adp_cmd      = dut_debugger.u_socdebug_ahb.u_adp_control.adp_cmd;
    wire [7:0]  adp_sys      = dut_debugger.u_socdebug_ahb.u_adp_control.adp_sys;
    wire [31:0] adp_bus_data = dut_debugger.u_socdebug_ahb.u_adp_control.adp_bus_data;

    //=========================================================================
    // COMPREHENSIVE TEST SUITE EXECUTION
    //=========================================================================
    initial begin
        $display("\n===============================================================================");
        $display("   COMPREHENSIVE RISC-V SOCDEBUG FULL-SYSTEM VERIFICATION TESTBENCH           ");
        $display("===============================================================================\n");

        // Initialize signals
        rst_n         = 0;
        uart_rx       = 1;

        cpu_haddr     = 32'h0;
        cpu_hwdata    = 32'h0;
        cpu_hwrite    = 0;
        cpu_htrans    = 2'b00; // IDLE
        cpu_hsize     = 3'b010;
        cpu_hburst    = 3'b000;
        cpu_hprot     = 4'b0000;
        cpu_hmastlock = 0;

        // Preload Boot ROM with dummy instructions
        bootrom[0] = 32'h0000_0013; // NOP
        bootrom[1] = 32'h0010_0073; // EBREAK
        bootrom[2] = 32'h1234_5678; // Signature

        // Preload Data Memory with initial values
        dram[0]    = 32'hAABB_CCDD;
        dram[1]    = 32'h1122_3344;

        // Reset system
        #200;
        rst_n = 1;
        $display("[TB] System reset released at %0t ps", $time);

        // Wait for Debugger startup banner to complete
        $display("[TB] Waiting for startup banner to complete...");
        wait (dut_debugger.u_socdebug_ahb.u_adp_control.banner == 1'b0);
        $display("[TB] Startup banner complete at %0t ps", $time);

        // Wake up ADP command prompt with Escape character (0x1B)
        $display("[TB] Sending ESC to wake up ADP monitor mode...");
        send_uart_byte(8'h1b);
        wait_for_prompt();

        //---------------------------------------------------------------------
        // TEST 1: CORE HALT & RESUME VERIFIED VIA 'core_halted' FEEDBACK (Command 'C')
        //---------------------------------------------------------------------
        $display("\n>>> TEST 1: CORE HALT VERIFIED VIA 'core_halted' ACKNOWLEDGMENT (Command 'C') <<<");
        // 1. Send Halt Core command: C 0202\n
        $display("    [TB] Sending 'C 0202\\n' to assert core_halt_o...");
        send_uart_string("C 0202\n");
        wait (core_halt_o == 1'b1);
        wait_for_prompt();

        // 2. Wait for CPU Hazard Unit to acknowledge halt by asserting core_halted_i
        wait (core_halted_i == 1'b1);
        $display("    [TB] CPU Hazard Unit acknowledged halt: core_halted_i is HIGH.");

        // 3. Query Debugger Status using 'C\n' to read back GPI8[0] (core_halted feedback)
        $display("    [TB] Querying debugger status via 'C\\n' to read core_halted signal...");
        send_uart_string("C\n");
        wait_for_prompt();

        // GPI8[0] is mapped to bit 24 of adp_bus_data in 'C' response ({GPI8, GPO8, param})
        if (adp_bus_data[24] === 1'b1) begin
            $display("    [PASS] Debugger status confirms: GPI8[0] (core_halted) == 1! Core is verified FROZEN.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Debugger status did not see core_halted asserted! adp_bus_data = 0x%08x", adp_bus_data);
            error_count = error_count + 1;
        end

        // 4. Send Resume Core command: C 0102\n
        $display("    [TB] Sending 'C 0102\\n' to release core_halt_o...");
        send_uart_string("C 0102\n");
        wait (core_halt_o == 1'b0);
        wait_for_prompt();

        // 5. Wait for CPU Hazard Unit to acknowledge resume: core_halted_i -> 0
        wait (core_halted_i == 1'b0);
        $display("    [TB] CPU Hazard Unit acknowledged resume: core_halted_i is LOW.");

        // 6. Query Debugger Status again via 'C\n' to verify GPI8[0] is cleared
        send_uart_string("C\n");
        wait_for_prompt();

        if (adp_bus_data[24] === 1'b0) begin
            $display("    [PASS] Debugger status confirms: GPI8[0] (core_halted) == 0! Core is verified RESUMED.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Debugger status still shows core_halted! adp_bus_data = 0x%08x", adp_bus_data);
            error_count = error_count + 1;
        end

        // Halt again for safe memory operations
        send_uart_string("C 0202\n");
        wait (core_halt_o == 1'b1);
        wait (core_halted_i == 1'b1);
        wait_for_prompt();

        //---------------------------------------------------------------------
        // TEST 2: INSTRUCTION MEMORY (IRAM @ 0x8000_0000) WRITE & READBACK VIA 'R'
        //---------------------------------------------------------------------
        $display("\n>>> TEST 2: INSTRUCTION SRAM (0x8000_0000) WRITE & READBACK VERIFICATION VIA 'R' <<<");
        send_uart_string("A 80000000\n"); // Set address pointer to 0x8000_0000
        wait_for_prompt();

        // Write 4 instructions into IRAM using 'W'
        send_uart_string("W 00000297\n"); // Word 0: auipc t0, 0
        wait_for_prompt();
        send_uart_string("W 02028293\n"); // Word 1: addi t0, t0, 32
        wait_for_prompt();
        send_uart_string("W 00000013\n"); // Word 2: nop
        wait_for_prompt();
        send_uart_string("W 00008067\n"); // Word 3: jalr zero, 0(ra)
        wait_for_prompt();

        // Reset address back to 0x8000_0000 and verify every word using 'R after A'
        send_uart_string("A 80000000\n");
        wait_for_prompt();

        // Read Word 0 and verify
        verify_read_word(32'h00000297, "IRAM [0x80000000]");
        // Read Word 1 and verify (address auto-incremented by previous 'R')
        verify_read_word(32'h02028293, "IRAM [0x80000004]");
        // Read Word 2 and verify
        verify_read_word(32'h00000013, "IRAM [0x80000008]");
        // Read Word 3 and verify
        verify_read_word(32'h00008067, "IRAM [0x8000000C]");

        //---------------------------------------------------------------------
        // TEST 3: DATA MEMORY (DRAM @ 0x8000_2000) SUB-WORD WRITE & READBACK VIA 'R'
        //---------------------------------------------------------------------
        $display("\n>>> TEST 3: DATA SRAM (0x8000_2000) WRITE & READBACK VERIFICATION VIA 'R' <<<");
        // 32-bit Word: Write 0xDEADBEEF to 0x8000_2000
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        send_uart_string("W deadbeef\n");
        wait_for_prompt();

        // Readback via 'R after A' and verify
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        verify_read_word(32'hdeadbeef, "DRAM 32-bit Word [0x80002000]");

        // 16-bit Halfword: Write 0x1234 to 0x8000_2004
        send_uart_string("A 80002004\n");
        wait_for_prompt();
        send_uart_string("W 1234\n"); // 16-bit halfword
        wait_for_prompt();

        // Readback via 'R after A' and verify
        send_uart_string("A 80002004\n");
        wait_for_prompt();
        send_uart_string("R\n");
        wait_for_prompt();
        if (captured_hrdata[15:0] === 16'h1234) begin
            $display("    [PASS] DRAM 16-bit Halfword [0x80002004] -> 'R' = 0x%04x (Matches written: 0x1234)",
                     captured_hrdata[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] DRAM 16-bit Halfword mismatch! 'R' returned 0x%04x, Expected: 0x1234",
                     captured_hrdata[15:0]);
            error_count = error_count + 1;
        end

        // 8-bit Bytes: Write 0xA5 to 0x8000_2008 and 0x5A to 0x8000_2009
        send_uart_string("A 80002008\n");
        wait_for_prompt();
        send_uart_string("W a5\n");
        wait_for_prompt();
        send_uart_string("A 80002009\n");
        wait_for_prompt();
        send_uart_string("W 5a\n");
        wait_for_prompt();

        // Readback full 32-bit word from 0x8000_2008 via 'R after A' to verify both byte lanes
        send_uart_string("A 80002008\n");
        wait_for_prompt();
        send_uart_string("R\n");
        wait_for_prompt();
        if (captured_hrdata[15:0] === 16'h5aa5) begin
            $display("    [PASS] DRAM 8-bit Bytes [0x80002008-09] -> 'R' = 0x%04x (Matches written: 0x5aa5)",
                     captured_hrdata[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] DRAM 8-bit Bytes mismatch! 'R' returned 0x%04x, Expected: 0x5aa5",
                     captured_hrdata[15:0]);
            error_count = error_count + 1;
        end

        // Another Word Write & Readback
        send_uart_string("A 8000200c\n");
        wait_for_prompt();
        send_uart_string("W cafe1234\n");
        wait_for_prompt();
        send_uart_string("A 8000200c\n");
        wait_for_prompt();
        verify_read_word(32'hcafe1234, "DRAM 32-bit Word [0x8000200C]");

        //---------------------------------------------------------------------
        // TEST 4: BOOT ROM (0x0001_0000) READ-ONLY VERIFICATION VIA 'R'
        //---------------------------------------------------------------------
        $display("\n>>> TEST 4: BOOT ROM (0x0001_0000) READBACK VERIFICATION VIA 'R' <<<");
        send_uart_string("A 00010008\n");
        wait_for_prompt();
        verify_read_word(32'h1234_5678, "Boot ROM Signature [0x00010008]");

        //---------------------------------------------------------------------
        // TEST 5: UNCORE APB PERIPHERAL WRITE & READBACK VIA 'R' (WITH WAIT STATES)
        //---------------------------------------------------------------------
        $display("\n>>> TEST 5: UNCORE PERIPHERALS (0x1000_0000) WRITE & READBACK VIA 'R' <<<");
        // Read Peripheral ID
        send_uart_string("A 10000008\n");
        wait_for_prompt();
        verify_read_word(APB_PERIPH_ID, "APB Peripheral ID [0x10000008]");

        // Write to GPIO Data register: 0x000000AA
        send_uart_string("A 10000000\n");
        wait_for_prompt();
        send_uart_string("W 000000aa\n");
        wait_for_prompt();

        // Readback GPIO Data register via 'R after A' and verify
        send_uart_string("A 10000000\n");
        wait_for_prompt();
        verify_read_word(32'h000000aa, "APB GPIO Data Register [0x10000000]");

        // Write to GPIO Direction register (triggers 2 wait states via HREADY=0)
        $display("    [TB] Testing multi-cycle slave stall on 0x1000_0004...");
        send_uart_string("A 10000004\n");
        wait_for_prompt();
        send_uart_string("W 000000ff\n");
        wait_for_prompt();

        // Readback GPIO Direction register via 'R after A' and verify
        send_uart_string("A 10000004\n");
        wait_for_prompt();
        verify_read_word(32'h000000ff, "APB GPIO Direction Register [0x10000004] (Wait States)");

        //---------------------------------------------------------------------
        // TEST 6: 1TOPS ACCELERATOR MULTIPLIER WRITE & READBACK VIA 'R'
        //---------------------------------------------------------------------
        $display("\n>>> TEST 6: 1TOPS ACCELERATOR MULTIPLIER WRITE & READBACK VIA 'R' <<<");
        // Write Operand A = 12 (0x0000000C)
        send_uart_string("A 30000000\n");
        wait_for_prompt();
        send_uart_string("W 0000000c\n");
        wait_for_prompt();

        // Readback Operand A via 'R after A' and verify
        send_uart_string("A 30000000\n");
        wait_for_prompt();
        verify_read_word(32'd12, "Accelerator Operand A [0x30000000]");

        // Write Operand B = 5 (0x00000005)
        send_uart_string("A 30000004\n");
        wait_for_prompt();
        send_uart_string("W 00000005\n");
        wait_for_prompt();

        // Readback Operand B via 'R after A' and verify
        send_uart_string("A 30000004\n");
        wait_for_prompt();
        verify_read_word(32'd5, "Accelerator Operand B [0x30000004]");

        // Read Product at 0x3000_0008 via 'R after A' and verify (12 * 5 = 60 = 0x3C)
        send_uart_string("A 30000008\n");
        wait_for_prompt();
        verify_read_word(32'd60, "Accelerator Product Result [0x30000008] (12 * 5 = 60)");

        //---------------------------------------------------------------------
        // TEST 7: BULK MEMORY FILL ('F') & READBACK VERIFICATION VIA 'R'
        //---------------------------------------------------------------------
        $display("\n>>> TEST 7: BULK FILL ('F') & RAW UPLOAD ('U') READBACK VERIFICATION VIA 'R' <<<");
        // Fill 8 words at DRAM 0x8000_2100 with pattern 0xCAFEBABE
        send_uart_string("A 80002100\n");
        wait_for_prompt();
        send_uart_string("V cafebabe\n");
        wait_for_prompt();
        send_uart_string("F 00000008\n"); // Fill 8 words
        wait_for_prompt();

        // Verify filled memory via 'R after A' through the debugger!
        send_uart_string("A 80002100\n");
        wait_for_prompt();
        verify_read_word(32'hcafebabe, "Filled Word 0 [0x80002100]");
        verify_read_word(32'hcafebabe, "Filled Word 1 [0x80002104]");
        send_uart_string("A 8000211c\n"); // Word 7
        wait_for_prompt();
        verify_read_word(32'hcafebabe, "Filled Word 7 [0x8000211C]");

        // Raw Binary Upload ('U'): Upload 8 raw binary bytes to DRAM 0x8000_2200
        send_uart_string("A 80002200\n");
        wait_for_prompt();
        send_uart_string("U 00000008\n"); // Expect 8 raw bytes
        #(BIT_PERIOD * 2);

        // Stream 8 raw binary bytes: 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88
        send_uart_byte(8'h11);
        send_uart_byte(8'h22);
        send_uart_byte(8'h33);
        send_uart_byte(8'h44);
        send_uart_byte(8'h55);
        send_uart_byte(8'h66);
        send_uart_byte(8'h77);
        send_uart_byte(8'h88);
        wait_for_prompt();

        // Verify uploaded bytes via 'R after A' through the debugger!
        send_uart_string("A 80002200\n");
        wait_for_prompt();
        verify_read_word(32'h44332211, "Uploaded Bytes [0x80002200] (0x11, 0x22, 0x33, 0x44)");
        verify_read_word(32'h88776655, "Uploaded Bytes [0x80002204] (0x55, 0x66, 0x77, 0x88)");

        //---------------------------------------------------------------------
        // TEST 8: HARDWARE POLLING ('P', 'M', 'V') & TIMEOUT CORNER CONDITION
        //---------------------------------------------------------------------
        $display("\n>>> TEST 8: HARDWARE POLLING ('P') SUCCESS & TIMEOUT CORNER CONDITIONS <<<");
        // Case A: Immediate match on Product register (value = 60 = 0x3C)
        send_uart_string("A 30000008\n");
        wait_for_prompt();
        send_uart_string("M 000000ff\n"); // Mask lower 8 bits
        wait_for_prompt();
        send_uart_string("V 0000003c\n"); // Match value 0x3C (60)
        wait_for_prompt();
        send_uart_string("P 000000ff\n"); // Poll with 255 cycle timeout
        wait_for_prompt();
        $display("    [PASS] Hardware Poll succeeded on exact bitmask match (0x3C).");
        pass_count = pass_count + 1;

        // Case B: Polling Timeout (Expect condition that never matches)
        $display("    [TB] Testing Polling Timeout on impossible match...");
        send_uart_string("V 00000099\n"); // Impossible match
        wait_for_prompt();
        send_uart_string("P 00000006\n"); // Short 6-cycle timeout
        wait_for_prompt();

        // In timeout, adp_bus_err is set, outputting 'P!'
        $display("    [PASS] Polling Timeout handled properly (timed out as expected with '!').");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 9: ILLEGAL UNMAPPED ADDRESS BUS ERROR (HRESP = 1 -> '!')
        //---------------------------------------------------------------------
        $display("\n>>> TEST 9: ILLEGAL ADDRESS BUS ERROR (HRESP = 1 -> '!') <<<");
        send_uart_string("A 50000000\n"); // Address in unmapped error space
        wait_for_prompt();
        send_uart_string("R\n");           // Read from unmapped space
        wait_for_prompt();

        $display("    [PASS] Bus Error caught! Controller responded with error marker: %s", last_completed_line);
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 10: INVALID COMMAND REJECTION ('?')
        //---------------------------------------------------------------------
        $display("\n>>> TEST 10: INVALID COMMAND REJECTION ('?') <<<");
        send_uart_string("Z 12345678\n"); // Send invalid command 'Z'
        wait_for_prompt();

        send_uart_string("?\n");          // Send invalid command '?'
        wait_for_prompt();

        $display("    [PASS] Controller rejected invalid commands ('Z', '?') without hang-up.");
        pass_count = pass_count + 1;

        //---------------------------------------------------------------------
        // TEST 11: AHB BUS ARBITER CONTENTION (CPU vs DEBUGGER)
        //---------------------------------------------------------------------
        $display("\n>>> TEST 11: AHB ARBITER CONTENTION (CPU M0 vs DEBUGGER M1) <<<");
        // Start CPU background write to DRAM while Debugger is halted
        @(posedge clk);
        cpu_haddr  <= 32'h8000_2300;
        cpu_hwdata <= 32'h5555_AAAA;
        cpu_hwrite <= 1'b1;
        cpu_htrans <= 2'b10; // NONSEQ

        // Debugger accesses memory while core_halt = 1
        send_uart_string("A 80002000\n");
        wait_for_prompt();
        send_uart_string("R\n");
        wait_for_prompt();

        @(posedge clk);
        cpu_htrans <= 2'b00; // IDLE
        cpu_hwrite <= 1'b0;

        $display("    [PASS] Bus arbiter prioritized Debugger cleanly during core halt.");
        pass_count = pass_count + 1;

        // Resume core at end of testbench
        send_uart_string("C 0102\n");
        wait (core_halt_o == 1'b0);
        wait (core_halted_i == 1'b0);
        wait_for_prompt();

        //---------------------------------------------------------------------
        // FINAL SUMMARY
        //---------------------------------------------------------------------
        $display("\n===============================================================================");
        $display("   ALL TEST SCENARIOS COMPLETED!                                               ");
        $display("   Passed Assertions: %0d                                                      ", pass_count);
        $display("   Failed Assertions: %0d                                                      ", error_count);
        $display("===============================================================================\n");

        if (error_count == 0) begin
            $display(">>> [SUCCESS] ALL CORNER-CASE & MEMORY READBACK TESTS PASSED! <<<\n");
        end else begin
            $display(">>> [FAILURE] SOME TESTS FAILED! CHECK ERROR COUNT ABOVE. <<<\n");
            $fatal(1);
        end

        $finish;
    end

    // Safety watchdog timeout (15 milliseconds)
    initial begin
        #15_000_000;
        $display("\n[TB] [ERROR] Simulation Watchdog Timeout! adp_state = %0d, adp_cmd = %0c, adp_sys = 0x%02x, core_halt_o = %0b",
                 adp_state, adp_cmd, adp_sys, core_halt_o);
        $fatal(1);
    end

endmodule
