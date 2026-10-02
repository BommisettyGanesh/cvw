//-----------------------------------------------------------------------------
// Testbench for SoCDebug Debugger Subsystem on RISC-V SoC (CORE-V Wally)
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_debugger;

    localparam CLK_FREQ   = 50_000_000;
    localparam BAUD_RATE  = 2_500_000; // High speed for fast simulation
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // in ns (400 ns)

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;

    wire core_halt_o;
    wire core_reset_o;
    reg  core_halted_i;

    // Debugger AHB Master Signals
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

    // Multiplexed Downstream AHB Slave Bus
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

    // Clock Generation (50 MHz = 20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Instantiate Top-level Debugger Subsystem
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
        .core_halted_i   (core_halted_i),
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

    // Instantiate AHB 2-to-1 Mux / Arbiter
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

    // Instantiate Dummy Multiplier Accelerator (0x30000000 region)
    wire accel_hsel = (s_haddr >= 32'h3000_0000) && (s_haddr <= 32'h30FF_FFFF);
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

    assign s_hready = accel_hsel ? accel_hreadyout : 1'b1;
    assign s_hresp  = accel_hsel ? accel_hresp      : 1'b0;
    assign s_hrdata = accel_hsel ? accel_hrdata     : 32'h0;

    // Track AHB transfers from debugger with proper pipelined data phase capture
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
            if (dbg_htrans == 2'b10 && dbg_hwrite == 1'b0) begin
                ahb_read_addr_phase <= 1'b1;
                captured_haddr      <= dbg_haddr;
            end else if (ahb_read_addr_phase && dbg_hready) begin
                ahb_read_addr_phase <= 1'b0;
                captured_hrdata     <= dbg_hrdata;
                ahb_read_done       <= 1'b1;
            end
        end
    end

    // Task to send a byte over UART RX pin
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
            #(BIT_PERIOD);
        end
    endtask

    // Task to send a string
    task send_uart_string(input string str);
        integer j;
        begin
            for (j = 0; j < str.len(); j = j + 1) begin
                send_uart_byte(str[j]);
            end
        end
    endtask

    // Task to wait for ADP command prompt (state 15: ADP_IOCHK)
    task wait_for_prompt;
        begin
            wait (dut_debugger.u_socdebug_ahb.u_adp_control.adp_state == 6'd15);
            #(BIT_PERIOD * 4);
        end
    endtask

    // Monitor ADP state transitions
    wire [5:0] adp_state = dut_debugger.u_socdebug_ahb.u_adp_control.adp_state;
    wire [7:0] adp_cmd   = dut_debugger.u_socdebug_ahb.u_adp_control.adp_cmd;
    wire [7:0] adp_sys   = dut_debugger.u_socdebug_ahb.u_adp_control.adp_sys;

    // Test Sequence
    initial begin
        $display("=========================================================");
        $display("   STARTING RISC-V SOCDEBUG INTEGRATION TESTBENCH        ");
        $display("=========================================================");

        // Initial values
        rst_n         = 0;
        uart_rx       = 1;
        core_halted_i = 0;

        cpu_haddr     = 32'h0;
        cpu_hwdata    = 32'h0;
        cpu_hwrite    = 0;
        cpu_htrans    = 2'b00; // IDLE
        cpu_hsize     = 3'b010;
        cpu_hburst    = 3'b000;
        cpu_hprot     = 4'b0000;
        cpu_hmastlock = 0;

        // Reset system
        #200;
        rst_n = 1;
        $display("[TB] System reset released at %0t ps", $time);

        // Preload dummy accelerator registers via CPU bus before halting:
        // Operand A = 7 (write to 0x30000000)
        // Operand B = 6 (write to 0x30000004)
        // Product should be 42 (0x2A) at 0x30000008
        #200;
        @(posedge clk);
        cpu_haddr  <= 32'h3000_0000;
        cpu_hwrite <= 1'b1;
        cpu_htrans <= 2'b10; // NONSEQ
        @(posedge clk);
        cpu_hwdata <= 32'd7;
        cpu_haddr  <= 32'h3000_0004;
        cpu_hwrite <= 1'b1;
        cpu_htrans <= 2'b10;
        @(posedge clk);
        cpu_hwdata <= 32'd6;
        cpu_htrans <= 2'b00; // IDLE
        @(posedge clk);
        cpu_hwrite <= 1'b0;

        $display("[TB] Preloaded Dummy Multiplier: OpA = 7, OpB = 6 -> Expected Product = 42 (0x2A)");

        // Wait for Debugger startup banner to complete
        $display("[TB] Waiting for startup banner to complete...");
        wait (dut_debugger.u_socdebug_ahb.u_adp_control.banner == 1'b0);
        $display("[TB] Startup banner complete at %0t ps", $time);

        // Wake up ADP command prompt with Escape char
        $display("[TB] Sending ESC to enter ADP mode...");
        send_uart_byte(8'h1b);
        wait_for_prompt();

        // TEST 1: HALT CORE
        // Send command: C 0202\n (Set bit 1 of GPO8 to assert core_halt_o)
        $display("\n--- TEST 1: HALT CORE VIA UART ---");
        $display("[TB] Sending 'C 0202\\n' to assert core_halt_o...");
        send_uart_string("C 0202\n");

        // Wait for processing and check core_halt_o
        wait (core_halt_o == 1'b1);
        $display("[TB] [SUCCESS] core_halt_o asserted to HIGH! RISC-V Core pipeline is now FROZEN.");
        core_halted_i = 1'b1; // Core reports it is halted
        wait_for_prompt();

        // TEST 2: READ ACCELERATOR VALUE OVER AHB WHILE CORE IS HALTED
        // Send command: A 30000008\n (Set address to product register)
        $display("\n--- TEST 2: FETCH ACCELERATOR PRODUCT OVER AHB WHILE HALTED ---");
        $display("[TB] Sending 'A 30000008\\n'...");
        send_uart_string("A 30000008\n");
        wait_for_prompt();

        // Send command: R\n (Read word)
        $display("[TB] Sending 'R\\n' to read 32-bit product from 0x30000008...");
        send_uart_string("R\n");

        // Wait for AHB transfer to complete
        wait (ahb_read_done == 1'b1);
        $display("[TB] [SUCCESS] AHB Read completed at address: 0x%08x", captured_haddr);
        $display("[TB] [SUCCESS] HRDATA returned by accelerator: 0x%08x (%0d)", captured_hrdata, captured_hrdata);

        if (captured_hrdata == 32'd42) begin
            $display("[TB] [VERIFIED] Product value matches expected 42 (0x2A)!");
        end else begin
            $display("[TB] [ERROR] Product mismatch! Expected 42, got %0d", captured_hrdata);
            $fatal(1);
        end
        wait_for_prompt();

        // TEST 3: RESUME CORE
        // Send command: C 0102\n (Clear bit 1 of GPO8 to deassert core_halt_o)
        $display("\n--- TEST 3: RESUME CORE VIA UART ---");
        $display("[TB] Sending 'C 0102\\n' to deassert core_halt_o...");
        send_uart_string("C 0102\n");

        wait (core_halt_o == 1'b0);
        $display("[TB] [SUCCESS] core_halt_o deasserted to LOW! RISC-V Core pipeline is now RESUMED.");
        core_halted_i = 1'b0;
        wait_for_prompt();

        $display("\n=========================================================");
        $display("   ALL DEBUGGER TESTS PASSED SUCCESSFULLY!               ");
        $display("=========================================================\n");
        $finish;
    end

    // Safety timeout: 5 milliseconds
    initial begin
        #5_000_000;
        $display("[TB] [ERROR] Simulation timeout! Current adp_state = %0d, adp_cmd = %0c, adp_sys = 0x%02x, core_halt_o = %0b",
                 adp_state, adp_cmd, adp_sys, core_halt_o);
        $finish;
    end

endmodule
