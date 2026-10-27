`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_core_berkeley.sv
// Purpose: PURE CPU CORE ONLY UC Berkeley Self-Checking Tests
//          Directly connects riscv_cpu to single-cycle AHB-Lite synchronous RAM
//          Monitors writes to `tohost`:
//            - 1         : PASS (All test assertions passed)
//            - (num<<1)|1: FAIL (Assertion #num failed)
// =============================================================================

module tb_core_berkeley;

    reg clk;
    reg rst_n;

    // CPU AHB Master Signals
    wire [31:0] HADDR, HWDATA, HRDATA;
    wire [ 3:0] HWSTRB;
    wire        HWRITE, HMASTLOCK, HREADY, HRESP;
    wire [ 2:0] HSIZE, HBURST;
    wire [ 3:0] HPROT;
    wire [ 1:0] HTRANS;

    wire [31:0] PC, PCW, ALUResultW, WriteDataW, Result;
    wire        InstrRetired, TrapM, mretM;

    // 2 MB Unified Memory Space (0x8000_0000 - 0x801F_FFFF)
    localparam MEM_SIZE_BYTES = 2097152;
    localparam MEM_WORDS      = MEM_SIZE_BYTES / 4;

    // Direct CPU Core Instantiation (Zero uncore, Zero peripherals)
    riscv_cpu #(
        .RESET_PC(32'h8000_0000)
    ) dut (
        .HCLK(clk),
        .HRESETn(rst_n),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HRDATA(HRDATA),
        .HREADY(HREADY),
        .HRESP(HRESP),
        .PC(PC),
        .PCW(PCW),
        .ALUResultW(ALUResultW),
        .WriteDataW(WriteDataW),
        .Result(Result),
        .MTimerInt(1'b0),
        .MSwInt(1'b0),
        .MExtInt(1'b0),
        .MTIME_CLINT(64'd0),
        .ExternalStall(1'b0),
        .InstrRetired(InstrRetired),
        .TrapM(TrapM),
        .mretM(mretM)
    );

    // Single-Cycle AHB Synchronous RAM
    ahb_ram #(
        .BASE_ADDR(32'h8000_0000),
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES),
        .DEFAULT_WAIT_STATES(0)
    ) ram_inst (
        .HCLK(clk),
        .HRESETn(rst_n),
        .HSEL(1'b1),
        .HADDR(HADDR),
        .HTRANS(HTRANS),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HREADY(HREADY),
        .HRDATA(HRDATA),
        .HREADYOUT(HREADY),
        .HRESP(HRESP)
    );

    // Clock generation (50 MHz, 20 ns period)
    always #10 clk = ~clk;

    // Command-line plusargs
    string hex_file;
    string test_name;
    reg [31:0] tohost_addr;
    integer max_cycles;
    integer cycle_count;
    integer instructions_retired;

    // Address Phase Latching for AHB Protocol
    reg        latched_write;
    reg [31:0] latched_addr;
    reg [ 3:0] latched_strb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_write <= 1'b0;
            latched_addr  <= 32'h0;
            latched_strb  <= 4'h0;
        end else if (HREADY) begin
            latched_write <= (HTRANS == 2'b10 || HTRANS == 2'b11) && HWRITE;
            latched_addr  <= HADDR;
            latched_strb  <= HWSTRB;
        end
    end

    // Instruction retirement counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instructions_retired <= 0;
            cycle_count          <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (InstrRetired) begin
                instructions_retired <= instructions_retired + 1;
            end
        end
    end

    // Monitor `tohost` Write
    always @(posedge clk) begin
        if (rst_n && latched_write && HREADY) begin
            if (latched_addr == tohost_addr) begin
                if (HWDATA == 32'h1) begin
                    $display("  [PASS] %-20s (tohost=1, Cycles: %0d, Retired: %0d, CPI: %0.2f)",
                             test_name, cycle_count, instructions_retired,
                             (instructions_retired > 0) ? (real'(cycle_count) / real'(instructions_retired)) : 0.0);
                    $finish;
                end else if (HWDATA[0] == 1'b1 && HWDATA > 32'h1) begin
                    $display("  [FAIL] %-20s Assertion #%0d FAILED! (tohost=0x%08x)",
                             test_name, (HWDATA >> 1), HWDATA);
                    $fatal(1);
                end
            end
        end
    end

    // Cycle limit guard
    always @(posedge clk) begin
        if (cycle_count > max_cycles) begin
            $display("  [TIMEOUT] %-20s Exceeded %0d cycles (PC: 0x%08x)",
                     test_name, max_cycles, PC);
            $fatal(1);
        end
    end

    // Simulation Setup
    initial begin
        clk   = 0;
        rst_n = 0;

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[-] ERROR: +HEX argument required!");
            $finish;
        end

        if (!$value$plusargs("NAME=%s", test_name)) begin
            test_name = hex_file;
        end

        if (!$value$plusargs("TOHOST=%x", tohost_addr)) begin
            tohost_addr = 32'h8000_1000;
        end

        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = 100000;
        end

        // Load HEX into AHB RAM
        $readmemh(hex_file, ram_inst.mem);

        // Apply Reset
        #45;
        rst_n = 1;
    end

endmodule
