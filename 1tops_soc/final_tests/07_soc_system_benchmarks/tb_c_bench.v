`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_c_bench
// Purpose: Verification & Benchmarking Testbench for Bare-Metal C Programs & CoreMark
//          Streams UART character output in real-time and monitors tohost termination
// =============================================================================

module tb_c_bench;

    reg clk;
    reg reset;

    wire        TrapM;
    wire        mretM;
    wire [31:0] PCW, ResultW;

    // 2 MB memory space (0x80000000 - 0x801FFFFF)
    // Split into 1 MB Instruction RAM (ram_i) + 1 MB Data RAM (ram_d)
    localparam MEM_SIZE_BYTES = 2097152;
    localparam MEM_WORDS      = MEM_SIZE_BYTES / 4;
    localparam IRAM_WORDS     = MEM_WORDS / 2;
    localparam DRAM_WORDS     = MEM_WORDS / 2;

    reg [31:0] preload_mem [0:MEM_WORDS-1];

    // Instantiate complete RISC-V AHB-Lite SoC
    riscv_soc_ahb #(
        .RESET_PC(32'h8000_0000),
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES)
    ) dut (
        .clk(clk),
        .reset(reset),
        .MExtInt(1'b0),
        .TrapM(TrapM),
        .mretM(mretM),
        .PCW(PCW),
        .ResultW(ResultW),
        .GPIOIN(32'd0),
        .GPIOOUT(),
        .GPIOEN(),
        .UARTSin(1'b1),
        .UARTSout(),
        .dbg_sel(1'b0),
        .uart_rx(1'b1),
        .uart_tx(),
        .ft1248_clk(),
        .ft1248_ss_n(),
        .ft1248_miso(1'b1),
        .ft1248_miosio(),
        .core_halted_led(),
        .SPIIn(1'b0),
        .SPIOut(),
        .SPICS(),
        .SPICLK()
    );

    // 100 MHz clock generation (10 ns period)
    always begin
        clk = 1'b0; #5;
        clk = 1'b1; #5;
    end

    reg [1023:0] hex_file;
    reg [31:0]   tohost_addr;
    integer      max_cycles;
    integer      cycles;
    integer      i;
    reg          halted;

    wire [31:0] tohost_word = (tohost_addr - 32'h80000000) >> 2;

    initial begin
        clk = 0;
        reset = 1;
        halted = 0;
        cycles = 0;

        for (i = 0; i < IRAM_WORDS; i = i + 1) dut.uncore.ram_i.mem[i] = 32'h00000000;
        for (i = 0; i < DRAM_WORDS; i = i + 1) dut.uncore.ram_d.mem[i] = 32'h00000000;
        for (i = 0; i < MEM_WORDS;  i = i + 1) preload_mem[i] = 32'h00000000;

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            hex_file = "test.hex";
        end
        if (!$value$plusargs("TOHOST=%x", tohost_addr)) begin
            tohost_addr = 32'h80001000;
        end
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = 10000000; // 10 million cycles default for benchmarks
        end

        #1;
        $readmemh(hex_file, preload_mem);
        for (i = 0; i < IRAM_WORDS; i = i + 1) begin
            dut.uncore.ram_i.mem[i] = preload_mem[i];
        end
        for (i = 0; i < DRAM_WORDS; i = i + 1) begin
            dut.uncore.ram_d.mem[i] = preload_mem[i + IRAM_WORDS];
        end

        $display("[TB] Loaded benchmark binary: %0s", hex_file);
        $display("[TB] Configured tohost address: 0x%08x (RAM word index: %0d)", tohost_addr, tohost_word);

        #50;
        reset = 0;
    end

    wire tohost_hit = (dut.uncore.ram_i.write_reg && (tohost_word < IRAM_WORDS) && (dut.uncore.ram_i.wr_addr_reg == tohost_word[17:0])) ||
                      (dut.uncore.ram_d.write_reg && (tohost_word >= IRAM_WORDS) && (dut.uncore.ram_d.wr_addr_reg == (tohost_word[17:0] - IRAM_WORDS[17:0])));

    // Cycle counter & tohost monitor
    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;

            // Detect memory write committing to tohost address
            if (tohost_hit && !halted) begin
                if (dut.HWDATA != 32'd0) begin
                    halted = 1;
                    $display("\n--------------------------------------------------");
                    $display("[TB] Benchmark Termination Detected at cycle %0d", cycles);
                    $display("[TB] Raw tohost value: 0x%08x", dut.HWDATA);
                    if (dut.HWDATA == 32'h1) begin
                        $display("[TB] Exit Code: 0 (SUCCESS)");
                    end else if (dut.HWDATA & 32'h1) begin
                        $display("[TB] Exit Code: %0d (FAILURE / ABORT)", dut.HWDATA >> 1);
                    end else begin
                        $display("[TB] tohost code: 0x%08x", dut.HWDATA);
                    end
                    $display("--------------------------------------------------\n");
                    repeat (20) @(posedge clk);
                    $finish;
                end
            end

            if (cycles >= max_cycles) begin
                $display("\n[TB ERROR] Simulation exceeded maximum cycle limit (%0d cycles)!", max_cycles);
                $display("[TB DEBUG] PCM=%h PCF=%h halted=%b", 
                         dut.cpu.dp.PCM, dut.cpu.dp.PC, halted);
                $finish;
            end
        end
    end

endmodule
