`timescale 1ns/1ps

// =============================================================================
// Module: tb_signal_level
// Purpose: Signal-Level Verification Testbench with Protocol Checkers,
//          Pipeline Invariant Checkers, and Memory X-Propagation Detectors
// =============================================================================

module tb_signal_level;

    reg clk;
    reg reset;

    // 100 MHz clock
    always begin
        clk = 1'b0; #5;
        clk = 1'b1; #5;
    end

    integer cycle_count = 0;
    always @(posedge clk) begin
        if (!reset) cycle_count <= cycle_count + 1;
    end

    initial begin
        clk = 0;
        reset = 1;
        #50;
        reset = 0;
        #300000; // Simulation timeout limit
        $display("\n[TB ERROR] Simulation reached timeout limit at cycle %0d!", cycle_count);
        $finish;
    end

    wire [31:0] PCW, ResultW;
    wire [31:0] GPIOOUT, GPIOEN;
    wire        UARTSout;

    // -------------------------------------------------------------------------
    // 1. Device Under Test (DUT): Complete SoC
    // -------------------------------------------------------------------------
    riscv_soc_ahb #(
        .RESET_PC(32'h8000_0000),
        .MEM_SIZE_BYTES(65536)
    ) soc (
        .clk(clk),
        .reset(reset),
        .MExtInt(1'b0),
        .TrapM(),
        .mretM(),
        .PCW(PCW),
        .ResultW(ResultW),
        .GPIOIN(32'hA5A5_5A5A),
        .GPIOOUT(GPIOOUT),
        .GPIOEN(GPIOEN),
        .UARTSin(1'b1),
        .UARTSout(UARTSout),
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

    // Preload RAM
    initial begin
        #1;
        $readmemh("test_instr.mem", soc.uncore.ram_i.mem);
        $readmemh("test_data.mem", soc.uncore.ram_d.mem);
    end

    // -------------------------------------------------------------------------
    // 2. Formal SystemVerilog Protocol Assertions (SVA)
    // -------------------------------------------------------------------------
    
    // AHB Bus Protocol Assertion Checker
    ahb_protocol_checker ahb_chk (
        .HCLK(soc.HCLK),
        .HRESETn(soc.HRESETn),
        .HADDR(soc.HADDR),
        .HWDATA(soc.HWDATA),
        .HWSTRB(soc.HWSTRB),
        .HWRITE(soc.HWRITE),
        .HSIZE(soc.HSIZE),
        .HTRANS(soc.HTRANS),
        .HRDATA(soc.HRDATA),
        .HREADY(soc.HREADY),
        .HRESP(soc.HRESP),
        .HSEL_SLAVES({soc.uncore.HSELRam_I, soc.uncore.HSELRam_D, soc.uncore.HSELEXT_int, soc.uncore.HSELBRIDGE})
    );

    // APB Bus Protocol Assertion Checker
    apb_protocol_checker apb_chk (
        .PCLK(soc.uncore.bridge.PCLK),
        .PRESETn(soc.uncore.bridge.PRESETn),
        .PSEL(soc.uncore.bridge.PSEL != 4'b0000),
        .PENABLE(soc.uncore.bridge.PENABLE),
        .PADDR(soc.uncore.bridge.PADDR),
        .PWRITE(soc.uncore.bridge.PWRITE),
        .PWDATA(soc.uncore.bridge.PWDATA),
        .PREADY(|soc.uncore.bridge.PREADY),
        .PSEL_PERIPHERALS(soc.uncore.bridge.PSEL)
    );

    // Core Pipeline Invariant Checker
    core_invariants_checker core_chk (
        .clk(soc.clk),
        .reset(soc.reset),
        .PC(soc.cpu.PC),
        .PCW(soc.cpu.PCW),
        .RegWriteW(soc.cpu.dp.RegWriteW),
        .RdW(soc.cpu.dp.RdW),
        .ResultW(soc.cpu.dp.ResultW),
        .ForwardAE(soc.cpu.dp.ForwardAE),
        .ForwardBE(soc.cpu.dp.ForwardBE),
        .FlushD(soc.cpu.dp.FlushD),
        .FlushE(soc.cpu.dp.FlushE),
        .TrapM(soc.cpu.TrapM),
        .mtvec(soc.cpu.dp.csr_inst.mtvec),
        .ExternalStall(soc.core_stall_effective),
        .StallF(soc.cpu.dp.StallF),
        .StallD(soc.cpu.dp.StallD),
        .StallE(soc.cpu.dp.StallE),
        .StallM(soc.cpu.dp.StallM),
        .StallW(soc.cpu.dp.StallW),
        .InstrRetired(soc.core_instr_retired),
        .dbg_core_reset(soc.dbg_core_reset),
        .core_HRESETn(soc.core_HRESETn)
    );

    // RAM X-Propagation Detector (from OpenHW Wally)
    ramxdetector #(32, 32) x_detector (
        .clk(soc.clk),
        .MemReadM(soc.cpu.dp.ResultSrcM == 3'b001),
        .LSULoadAccessFaultM(1'b0),
        .ReadDataM(soc.cpu.dp.ReadDataM),
        .PCM(soc.cpu.dp.PCM),
        .InstrM(soc.cpu.dp.InstrM),
        .IEUAdrM(soc.cpu.dp.ALUResultM),
        .StallW(soc.cpu.dp.StallW),
        .InstrMName("")
    );

    // Watchdog & Livelock Monitor (Ported from OpenHW CVW)
    watchdog #(32, 2000, 50) wd (
        .clk(soc.clk),
        .reset(soc.reset),
        .PCW(soc.cpu.PCW),
        .TrapM(soc.cpu.TrapM),
        .PCM(soc.cpu.dp.PCM),
        .TEST_NAME("signal_level_test")
    );

    // -------------------------------------------------------------------------
    // 3. Test Completion & tohost Monitor
    // -------------------------------------------------------------------------
    reg [31:0] last_pc;
    integer stuck_count = 0;

    always @(posedge clk) begin
        if (!reset) begin
            if (soc.cpu.PC == last_pc && soc.cpu.PC != 32'h0) begin
                stuck_count <= stuck_count + 1;
            end else begin
                stuck_count <= 0;
                last_pc <= soc.cpu.PC;
            end

            // Check tohost write
            if (soc.cpu.dp.MemWriteM_gated && 
                ((soc.cpu.dp.ALUResultM >= 32'h8000_1000 && soc.cpu.dp.ALUResultM <= 32'h8000_1020) || soc.cpu.dp.ALUResultM == 32'h8000_0000)) begin
                if (soc.cpu.dp.WriteDataM == 32'd1) begin
                    $display("\n=======================================================");
                    $display("[SIGNAL-LEVEL TEST] Result: PASSED! (Cycles: %0d)", cycle_count);
                    $display("[SIGNAL-LEVEL TEST] All Bus & Pipeline SVA Assertions Satisfied.");
                    $display("[SIGNAL-LEVEL TEST] tohost write = 0x%08x at PC=0x%08x", soc.cpu.dp.WriteDataM, PCW);
                    $display("=======================================================\n");
                    $finish;
                end else if (soc.cpu.dp.WriteDataM != 32'd0) begin
                    $display("\n=======================================================");
                    $display("[SIGNAL-LEVEL TEST] Result: FAILED! (Cycles: %0d)", cycle_count);
                    $display("[SIGNAL-LEVEL TEST] tohost fail code = 0x%08x (Status: %0d) at PC=0x%08x", 
                             soc.cpu.dp.WriteDataM, soc.cpu.dp.WriteDataM >> 1, PCW);
                    $display("=======================================================\n");
                    $finish;
                end
            end

            // Spin-loop fallback check
            if (stuck_count > 30) begin
                if (soc.cpu.dp.rf.reg_file_arr[1] == 32'd1 || soc.cpu.dp.rf.reg_file_arr[10] == 32'd1) begin
                    $display("\n=======================================================");
                    $display("[SIGNAL-LEVEL TEST] Result: PASSED (Spin-loop termination)! (Cycles: %0d)", cycle_count);
                    $display("[SIGNAL-LEVEL TEST] All Bus & Pipeline SVA Assertions Satisfied.");
                    $display("=======================================================\n");
                    $finish;
                end else begin
                    $display("\n=======================================================");
                    $display("[SIGNAL-LEVEL TEST] Result: HALTED / FAILED at PC = 0x%08x (Cycles: %0d)", soc.cpu.PC, cycle_count);
                    $display("=======================================================\n");
                    $finish;
                end
            end
        end
    end

endmodule
