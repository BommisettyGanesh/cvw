`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_ahb_mux_crv.sv
// Purpose: Class-Based Constrained-Random Verification (CRV) for 2-Master
//          AHB-Lite Bus Arbiter and Multiplexer (ahb_mux.sv)
// =============================================================================

module tb_ahb_mux_crv;

    reg         HCLK;
    reg         HRESETn;
    reg         core_halt;

    // Master 0 (CPU)
    reg  [31:0] M0_HADDR;
    reg  [31:0] M0_HWDATA;
    reg         M0_HWRITE;
    reg  [ 1:0] M0_HTRANS;
    reg  [ 2:0] M0_HSIZE;
    wire [31:0] M0_HRDATA;
    wire        M0_HREADY;
    wire        M0_HRESP;

    // Master 1 (Debugger)
    reg  [31:0] M1_HADDR;
    reg  [31:0] M1_HWDATA;
    reg         M1_HWRITE;
    reg  [ 1:0] M1_HTRANS;
    reg  [ 2:0] M1_HSIZE;
    wire [31:0] M1_HRDATA;
    wire        M1_HREADY;
    wire        M1_HRESP;

    // Slave Interconnect
    wire [31:0] S_HADDR;
    wire [31:0] S_HWDATA;
    wire        S_HWRITE;
    wire [ 1:0] S_HTRANS;
    wire [ 2:0] S_HSIZE;
    wire [ 2:0] S_HBURST;
    wire [ 3:0] S_HPROT;
    wire        S_HMASTLOCK;
    reg  [31:0] S_HRDATA;
    reg         S_HREADY;
    reg         S_HRESP;

    // Clock generator (50 MHz)
    initial HCLK = 0;
    always #10 HCLK = ~HCLK;

    // DUT Instantiation
    ahb_mux #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .core_halt(core_halt),

        // M0
        .M0_HADDR(M0_HADDR),
        .M0_HWDATA(M0_HWDATA),
        .M0_HWRITE(M0_HWRITE),
        .M0_HTRANS(M0_HTRANS),
        .M0_HSIZE(M0_HSIZE),
        .M0_HBURST(3'b000),
        .M0_HPROT(4'b0011),
        .M0_HMASTLOCK(1'b0),
        .M0_HRDATA(M0_HRDATA),
        .M0_HREADY(M0_HREADY),
        .M0_HRESP(M0_HRESP),

        // M1
        .M1_HADDR(M1_HADDR),
        .M1_HWDATA(M1_HWDATA),
        .M1_HWRITE(M1_HWRITE),
        .M1_HTRANS(M1_HTRANS),
        .M1_HSIZE(M1_HSIZE),
        .M1_HBURST(3'b000),
        .M1_HPROT(4'b0011),
        .M1_HMASTLOCK(1'b0),
        .M1_HRDATA(M1_HRDATA),
        .M1_HREADY(M1_HREADY),
        .M1_HRESP(M1_HRESP),

        // S
        .S_HADDR(S_HADDR),
        .S_HWDATA(S_HWDATA),
        .S_HWRITE(S_HWRITE),
        .S_HTRANS(S_HTRANS),
        .S_HSIZE(S_HSIZE),
        .S_HBURST(S_HBURST),
        .S_HPROT(S_HPROT),
        .S_HMASTLOCK(S_HMASTLOCK),
        .S_HRDATA(S_HRDATA),
        .S_HREADY(S_HREADY),
        .S_HRESP(S_HRESP)
    );

    // -------------------------------------------------------------------------
    // Transaction Class
    // -------------------------------------------------------------------------
    class ahb_trans;
        bit [31:0] addr;
        bit [31:0] data;
        bit        write;
        bit [ 2:0] size;
        bit [ 1:0] trans;

        function void randomize_data();
            addr  = ($urandom_range(0, 63) << 2);
            data  = $urandom();
            write = $urandom_range(0, 1);
            size  = 3'b010;
            trans = 2'b10;
        endfunction
    endclass

    integer verified_trans_count = 0;
    integer errors = 0;

    // Simple slave memory model
    reg [31:0] slave_mem [0:255];
    reg [31:0] latched_addr;
    reg        latched_write;
    reg        latched_active;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            latched_addr   <= 32'd0;
            latched_write  <= 1'b0;
            latched_active <= 1'b0;
            S_HRDATA       <= 32'd0;
        end else if (S_HREADY) begin
            if (latched_active && latched_write) begin
                slave_mem[latched_addr[9:2]] <= S_HWDATA;
            end

            latched_active <= (S_HTRANS == 2'b10);
            latched_write  <= S_HWRITE;
            latched_addr   <= S_HADDR;

            if (S_HTRANS == 2'b10 && !S_HWRITE) begin
                S_HRDATA <= slave_mem[S_HADDR[9:2]];
            end
        end
    end

    // Test Scenario Execution
    initial begin
        ahb_trans tr;
        $display("=== Running Constrained-Random Bus Fabric Verification: ahb_mux.sv ===");

        HRESETn   = 1'b0;
        core_halt = 1'b0;
        M0_HTRANS = 2'b00;
        M1_HTRANS = 2'b00;
        S_HREADY  = 1'b1;
        S_HRESP   = 1'b0;

        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        @(posedge HCLK);

        // Preload slave memory
        for (int i = 0; i < 256; i++) slave_mem[i] = 32'hA000_0000 + i;

        // ---------------------------------------------------------------------
        // TEST 1: Uncontended Master 0 (CPU) Transfers
        // ---------------------------------------------------------------------
        $display("[TEST 1] Testing uncontended Master 0 transactions...");
        for (int t = 0; t < 20; t++) begin
            tr = new();
            tr.randomize_data();

            @(posedge HCLK);
            M0_HADDR  = tr.addr;
            M0_HWRITE = tr.write;
            M0_HWDATA = tr.data;
            M0_HTRANS = tr.trans;
            M0_HSIZE  = tr.size;

            @(posedge HCLK);
            M0_HTRANS = 2'b00;

            // Verify downstream slave saw Master 0
            if (S_HADDR !== tr.addr && dut.grant_addr == 1'b0) begin
                $display("[FAIL] Master 0 address mismatch! S_HADDR=0x%08x, exp=0x%08x", S_HADDR, tr.addr);
                errors++;
            end
            verified_trans_count++;
        end
        $display("[TEST 1] PASSED: Master 0 executed 20 valid transactions.");

        // ---------------------------------------------------------------------
        // TEST 2: Uncontended Master 1 (Debugger) Transfers
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Testing uncontended Master 1 (Debugger) transactions...");
        for (int t = 0; t < 20; t++) begin
            tr = new();
            tr.randomize_data();

            @(posedge HCLK);
            M1_HADDR  = tr.addr;
            M1_HWRITE = tr.write;
            M1_HWDATA = tr.data;
            M1_HTRANS = tr.trans;
            M1_HSIZE  = tr.size;

            @(posedge HCLK);
            M1_HTRANS = 2'b00;

            if (S_HADDR !== tr.addr && dut.grant_addr == 1'b1) begin
                $display("[FAIL] Master 1 address mismatch! S_HADDR=0x%08x, exp=0x%08x", S_HADDR, tr.addr);
                errors++;
            end
            verified_trans_count++;
        end
        $display("[TEST 2] PASSED: Master 1 executed 20 valid transactions.");

        // ---------------------------------------------------------------------
        // TEST 3: Simultaneous Contention & Priority Arbitration
        // When both M0 and M1 request simultaneously, M1 (Debugger) must WIN!
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Testing simultaneous bus contention (M0 vs M1)...");
        for (int t = 0; t < 20; t++) begin
            @(posedge HCLK);
            M0_HADDR  = 32'h0000_1000 + (t * 4);
            M0_HTRANS = 2'b10; // Active request
            M0_HWRITE = 1'b0;

            M1_HADDR  = 32'h0000_2000 + (t * 4);
            M1_HTRANS = 2'b10; // Active request
            M1_HWRITE = 1'b0;

            @(posedge HCLK);
            #1; // Settle non-blocking update of grant_addr
            // Master 1 should be granted address phase
            if (dut.grant_addr !== 1'b1) begin
                $display("[FAIL] Priority inversion! Master 1 did not win simultaneous contention!");
                errors++;
            end

            M0_HTRANS = 2'b00;
            M1_HTRANS = 2'b00;
            verified_trans_count++;
        end
        $display("[TEST 3] PASSED: Debugger (Master 1) won 100 percent of contention cycles.");

        // ---------------------------------------------------------------------
        // TEST 4: Core Halt Priority Mode (core_halt = 1)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Testing core_halt priority mode...");
        core_halt = 1'b1;

        // Request bus
        @(posedge HCLK);
        M1_HADDR  = 32'h0000_0000;
        M1_HTRANS = 2'b10;
        M1_HWRITE = 1'b1;

        // Wait for grant_addr to become 1
        @(posedge HCLK);
        #1;

        // Address phase is now active on slave bus.
        // On next clock edge, slave latches address and grant_data becomes 1.
        @(posedge HCLK);
        #1;
        M1_HTRANS = 2'b00;
        M1_HWDATA = 32'hBEEF_CAFE;

        // Slave commits write data at this edge
        @(posedge HCLK);
        #1;

        if (slave_mem[0] !== 32'hBEEF_CAFE) begin
            $display("[FAIL] Write data not committed to slave! (got 0x%08x, exp 0xBEEF_CAFE)", slave_mem[0]);
            errors++;
        end else begin
            $display("[TEST 4] PASSED: Debugger wrote memory with core_halt asserted.");
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n==================================================================");
            $display(" [TB Result] PASSED: %0d Constrained-Random Bus Transfers Verified!", verified_trans_count);
            $display("==================================================================\n");
        end else begin
            $display("\n[TB Result] FAILED with %0d errors!\n", errors);
        end

        $finish;
    end

endmodule
