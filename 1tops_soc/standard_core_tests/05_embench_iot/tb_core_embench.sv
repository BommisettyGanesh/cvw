`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_core_embench.sv
// Purpose: PURE CPU CORE ONLY Embench-IoT Benchmark Kernel Execution
//          Directly connects riscv_cpu to single-cycle AHB-Lite synchronous RAM
//          Memory Map:
//            - 0x8000_0000 : 2 MB AHB RAM (Code, Data, Heap, Stack)
//            - 0x8000_1000 : Character Console Output
//            - 0x8000_1004 : Benchmark Status (1 = PASS, Kernel Validated)
// =============================================================================

module tb_core_embench;

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

    // Metrics counters
    integer cycle_count;
    integer instructions_retired;
    localparam MAX_CYCLES = 3000000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count          <= 0;
            instructions_retired <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (InstrRetired) begin
                instructions_retired <= instructions_retired + 1;
            end
        end
    end

    // Periodic simulation progress monitor
    always @(posedge clk) begin
        if (rst_n && (cycle_count % 100000 == 0) && cycle_count > 0) begin
            $display("  [SIM PROGRESS] Cycle: %0d | Retired: %0d | Current PC: 0x%08x",
                     cycle_count, instructions_retired, PC);
            $fflush();
        end
    end

    // Stream Console & Monitor Completion
    always @(posedge clk) begin
        if (rst_n && latched_write && HREADY) begin
            // Console output port
            if (latched_addr == 32'h8000_1000) begin
                $write("%c", HWDATA[7:0]);
                $fflush();
            end
            // Benchmark completion port
            else if (latched_addr == 32'h8000_1004) begin
                if (HWDATA == 32'h1) begin
                    $display("\n>>> [PASS] Embench-IoT Benchmark Completed & Verified! <<<");
                    $display("    Total Cycles: %0d | Instructions Retired: %0d | Overall CPI: %0.2f\n",
                             cycle_count, instructions_retired,
                             (instructions_retired > 0) ? (real'(cycle_count) / real'(instructions_retired)) : 0.0);
                    $finish;
                end else begin
                    $display("\n>>> [FAIL] Embench Benchmark Verification Failed! (tohost=0x%08x) <<<", HWDATA);
                    $fatal(1);
                end
            end
        end
    end

    // Watchdog
    always @(posedge clk) begin
        if (cycle_count > MAX_CYCLES) begin
            $display("\n>>> [TIMEOUT] Embench simulation exceeded %0d cycles (PC: 0x%08x) <<<",
                     MAX_CYCLES, PC);
            $fatal(1);
        end
    end

    string hex_file;

    // Simulation Setup
    initial begin
        clk   = 0;
        rst_n = 0;

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            hex_file = "build/embench.hex";
        end

        $readmemh(hex_file, ram_inst.mem);

        #45;
        rst_n = 1;
    end

endmodule
