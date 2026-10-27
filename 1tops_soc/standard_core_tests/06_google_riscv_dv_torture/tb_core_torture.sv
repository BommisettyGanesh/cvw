`timescale 1ns/1ps

module tb_core_torture;

    reg clk;
    reg rst_n;

    // AHB-Lite Core Signals
    wire [31:0] HADDR;
    wire [2:0]  HBURST;
    wire        HMASTLOCK;
    wire [3:0]  HPROT;
    wire [2:0]  HSIZE;
    wire [1:0]  HTRANS;
    wire [31:0] HWDATA;
    wire        HWRITE;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;

    // Core Extra Status / Debug Ports
    reg         dbg_external_stall;
    reg         dbg_core_reset;
    wire        InstrRetired;
    wire [31:0] PC;

    // Clock generator (50 MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // Instantiate Pure CPU Core (riscv_cpu)
    riscv_cpu #(
        .RESET_PC(32'h8000_0000)
    ) u_core (
        .clk                (clk),
        .rst_n              (rst_n && !dbg_core_reset),
        .HADDR              (HADDR),
        .HBURST             (HBURST),
        .HMASTLOCK          (HMASTLOCK),
        .HPROT              (HPROT),
        .HSIZE              (HSIZE),
        .HTRANS             (HTRANS),
        .HWDATA             (HWDATA),
        .HWRITE             (HWRITE),
        .HRDATA             (HRDATA),
        .HREADY             (HREADY),
        .HRESP              (HRESP),
        .ExternalStall      (dbg_external_stall),
        .InstrRetired       (InstrRetired),
        .CurrentPC          (PC)
    );

    // Instantiate Single-Cycle AHB RAM
    ahb_ram #(
        .BASE_ADDR(32'h8000_0000),
        .RAM_SIZE (2097152) // 2 MB
    ) u_ram (
        .HCLK     (clk),
        .HRESETn  (rst_n),
        .HSEL     (HTRANS != 2'b00 && HADDR >= 32'h8000_0000 && HADDR < 32'h8020_0000),
        .HADDR    (HADDR),
        .HTRANS   (HTRANS),
        .HWRITE   (HWRITE),
        .HSIZE    (HSIZE),
        .HWDATA   (HWDATA),
        .HREADY   (HREADY),
        .HREADYOUT(HREADY),
        .HRDATA   (HRDATA),
        .HRESP    (HRESP)
    );

    // Hex file loader
    string hex_file;
    initial begin
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[-] ERROR: No +HEX=<file.hex> argument provided!");
            $finish;
        end
        $readmemh(hex_file, u_ram.mem);
    end

    // Latched write tracking for AHB address-data phases
    reg [31:0] latched_addr;
    reg        latched_write;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr  <= 32'h0;
            latched_write <= 1'b0;
        end else if (HREADY) begin
            latched_addr  <= HADDR;
            latched_write <= (HTRANS == 2'b10 || HTRANS == 2'b11) && HWRITE;
        end
    end

    // Metrics tracking
    integer cycle_count;
    integer instructions_retired;
    localparam MAX_CYCLES = 500000;

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

    // Monitor completion via tohost (0x80001004)
    always @(posedge clk) begin
        if (rst_n && latched_write && HREADY) begin
            // Console streaming
            if (latched_addr == 32'h8000_1000) begin
                $write("%c", HWDATA[7:0]);
                $fflush();
            end
            // tohost status mailbox
            else if (latched_addr == 32'h8000_1004) begin
                if (HWDATA == 32'h1) begin
                    $display("\n>>> [PASS] Torture Test PASSED! <<<");
                    $display("    Cycles: %0d | Instructions: %0d | Core CPI: %0.2f\n",
                             cycle_count, instructions_retired,
                             real'(cycle_count) / real'(instructions_retired > 0 ? instructions_retired : 1));
                    $finish;
                end else begin
                    $display("\n>>> [FAIL] Torture Test FAILED! (Fail Code = 0x%08x, Subtest #%0d) <<<", 
                             HWDATA, (HWDATA >> 1));
                    $fatal(1, "Torture Test Failure detected!");
                end
            end
        end

        if (cycle_count >= MAX_CYCLES) begin
            $display("\n[-] ERROR: Torture Test TIMEOUT after %0d cycles! (PC: 0x%08x)", MAX_CYCLES, PC);
            $fatal(1, "Simulation Timeout");
        end
    end

    // Reset sequence
    initial begin
        dbg_external_stall = 0;
        dbg_core_reset     = 0;
        rst_n              = 0;
        #100;
        @(negedge clk);
        rst_n = 1;
    end

endmodule
