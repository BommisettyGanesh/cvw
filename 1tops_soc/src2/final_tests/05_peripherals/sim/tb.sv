`timescale 1ns/1ps

// =============================================================================
// Module: tb (OpenHW CVW Compatible SoC & Module Level Testbench)
// Reference: cvw/testbench/testbench.sv & cvw/1tops_soc/testbench/tb.sv
// =============================================================================

module tb(
`ifdef VERILATOR
  input logic clk,
  input logic reset
`endif
);

`ifndef VERILATOR
  reg clk;
  reg reset;

  // 100 MHz clock (10 ns period)
  always begin
    clk = 1'b0; #5;
    clk = 1'b1; #5;
  end

  initial begin
    clk = 0;
    reset = 1;
    #50;
    reset = 0;
    #250000; // Simulation timeout limit
    $display("\n[TB ERROR] Simulation reached timeout limit!");
    $finish;
  end
`endif

  wire [31:0] PCW, ResultW;
  wire [31:0] GPIOOUT, GPIOEN;
  wire        UARTSout;

  // Top-level SoC Instantiation (Configured with 64KB address space for full test vectors)
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
    .GPIOIN(32'hA5A5_5A5A), // Loopback/stimulus pattern for GPIO inputs
    .GPIOOUT(GPIOOUT),
    .GPIOEN(GPIOEN),
    .UARTSin(1'b1),        // UART idle high
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

  // Preload independent Instruction and Data RAMs
  initial begin
    #1;
    $readmemh("test_instr.mem", soc.uncore.ram_i.mem);
    $readmemh("test_data.mem", soc.uncore.ram_d.mem);
  end

  // Test Execution & Completion Monitor (OpenHW CVW tohost Protocol)
  reg [31:0] last_pc;
  integer stuck_count = 0;

  always @(posedge clk) begin
    if (!reset) begin
      // Track stuck PC (e.g., spin loop at write_tohost or test finish)
      if (soc.cpu.PC == last_pc && soc.cpu.PC != 32'h0000_0000) begin
        stuck_count <= stuck_count + 1;
      end else begin
        stuck_count <= 0;
        last_pc <= soc.cpu.PC;
      end

      // 1. Check Store to tohost
      if (soc.cpu.dp.MemWriteM_gated) begin
        // Check if writing to tohost (0x8000_1000 or 0x8000_0000)
        if (soc.cpu.dp.ALUResultM == 32'h8000_1000 || soc.cpu.dp.ALUResultM == 32'h8000_0000) begin
          if (soc.cpu.dp.WriteDataM == 32'd1) begin
            $display("\n=======================================================");
            $display("[TB] Test Result: PASSED!");
            $display("[TB] tohost signature write = 0x%08x at PC=0x%08x", soc.cpu.dp.WriteDataM, PCW);
            $display("=======================================================\n");
            $finish;
          end else if (soc.cpu.dp.WriteDataM != 32'd0) begin
            $display("\n=======================================================");
            $display("[TB] Test Result: FAILED!");
            $display("[TB] tohost fail code = 0x%08x (Status: %0d) at PC=0x%08x", 
                     soc.cpu.dp.WriteDataM, soc.cpu.dp.WriteDataM >> 1, PCW);
            $display("=======================================================\n");
            $finish;
          end
        end
      end

      // 2. Fallback: if core enters spin-loop for > 20 cycles, evaluate registers
      if (stuck_count > 25) begin
        // Check register x1 (ra) or x3 (gp)
        if (soc.cpu.dp.rf.reg_file_arr[1] == 32'd1 || soc.cpu.dp.rf.reg_file_arr[3] == 32'd1) begin
          $display("\n=======================================================");
          $display("[TB] Test Result: PASSED (Spin-loop termination)!");
          $display("[TB] Final PC = 0x%08x, x1(ra) = %0d, x3(gp) = %0d", 
                   soc.cpu.PC, soc.cpu.dp.rf.reg_file_arr[1], soc.cpu.dp.rf.reg_file_arr[3]);
          $display("=======================================================\n");
          $finish;
        end else begin
          $display("\n=======================================================");
          $display("[TB] Test Result: HALTED / FAILED at PC = 0x%08x", soc.cpu.PC);
          $display("[TB] x1(ra) = 0x%08x, x3(gp) = 0x%08x, x10(a0) = 0x%08x", 
                   soc.cpu.dp.rf.reg_file_arr[1], soc.cpu.dp.rf.reg_file_arr[3], soc.cpu.dp.rf.reg_file_arr[10]);
          $display("=======================================================\n");
          $finish;
        end
      end
    end
  end

endmodule
