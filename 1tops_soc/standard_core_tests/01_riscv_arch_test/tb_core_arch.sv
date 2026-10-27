`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_core_arch.sv
// Purpose: PURE CPU CORE ONLY Architectural Verification against Golden Model
//          Directly connects riscv_cpu to single-cycle AHB-Lite synchronous RAM
//          Dumps signature from begin_signature to end_signature for comparison
// =============================================================================

module tb_core_arch;

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

    // Direct AHB-Lite RAM Instantiation (Single-cycle response)
    ahb_ram #(
        .BASE_ADDR(32'h8000_0000),
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES),
        .DEFAULT_WAIT_STATES(0)
    ) ram (
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

    // 100 MHz clock generation (10 ns period)
    always begin
        clk = 1'b0; #5;
        clk = 1'b1; #5;
    end

    // Test parameters passed from runner script via plusargs
    reg [1023:0] hex_file;
    reg [1023:0] sig_file;
    reg [31:0]   tohost_addr;
    reg [31:0]   begin_sig_addr;
    reg [31:0]   end_sig_addr;
    integer      max_cycles;
    integer      cycles;
    integer      f_sig;
    integer      i;
    reg          halted;

    function [31:0] read_mem_word(input [31:0] byte_addr);
        integer w;
        begin
            w = (byte_addr - 32'h8000_0000) >> 2;
            if (w < MEM_WORDS)
                read_mem_word = ram.mem[w];
            else
                read_mem_word = 32'h0;
        end
    endfunction

    initial begin
        rst_n = 0;
        cycles = 0;
        halted = 0;

        // Query simulation plusargs
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[TB ERROR] No +HEX=<file.hex> argument provided!");
            $finish;
        end
        if (!$value$plusargs("SIG=%s", sig_file)) begin
            sig_file = "dut.signature";
        end
        if (!$value$plusargs("TOHOST=%x", tohost_addr)) begin
            tohost_addr = 32'h8000_1000;
        end
        if (!$value$plusargs("BEGIN_SIG=%x", begin_sig_addr)) begin
            begin_sig_addr = 32'h0;
        end
        if (!$value$plusargs("END_SIG=%x", end_sig_addr)) begin
            end_sig_addr = 32'h0;
        end
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = 100000;
        end

        // Preload memory
        $readmemh(hex_file, ram.mem);

        // Reset sequence
        repeat(5) @(posedge clk);
        rst_n = 1;
        $display("[TB CORE ARCH] CPU Core reset deasserted. Running...");
    end

    // Track write to tohost
    reg        latched_write;
    reg [31:0] latched_addr;
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;

            if (latched_write && HREADY) begin
                if (latched_addr == tohost_addr) begin
                    $display("[TB CORE ARCH] tohost write detected: 0x%08x at cycle %0d (PC=0x%08x)", HWDATA, cycles, PCW);
                    halted = 1'b1;
                end
            end

            latched_write <= HWRITE && HREADY && HTRANS[1];
            latched_addr  <= HADDR;

            if (halted || cycles >= max_cycles) begin
                if (cycles >= max_cycles)
                    $display("[TB CORE ARCH WARNING] Reached maximum cycle limit (%0d)", max_cycles);

                // Dump signature block to signature file
                if (end_sig_addr > begin_sig_addr) begin
                    f_sig = $fopen(sig_file, "w");
                    if (f_sig != 0) begin
                        for (i = begin_sig_addr; i < end_sig_addr; i = i + 4) begin
                            $fwrite(f_sig, "%08x\n", read_mem_word(i));
                        end
                        $fclose(f_sig);
                        $display("[TB CORE ARCH] Signature dumped to %0s (0x%08x - 0x%08x)", sig_file, begin_sig_addr, end_sig_addr);
                    end else begin
                        $display("[TB CORE ARCH ERROR] Could not open signature file %0s for writing!", sig_file);
                    end
                end

                $finish;
            end
        end
    end

endmodule
