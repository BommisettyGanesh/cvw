// =============================================================================
// Module: ahb_ram
// Purpose: AMBA 3 AHB-Lite Synchronous RAM with Byte Enables & Configurable
//          Wait-State Stress Injection (Fixed or Pseudo-Random LFSR)
// =============================================================================

module ahb_ram #(
    parameter BASE_ADDR           = 32'h8000_0000,
    parameter MEM_SIZE_BYTES      = 16384, // 16 KB default (overridden in uncore or testbench)
    parameter DEFAULT_WAIT_STATES = 0
)(
    input             HCLK,
    input             HRESETn,
    input             HSEL,
    input      [31:0] HADDR,
    input      [ 1:0] HTRANS,
    input             HWRITE,
    input      [ 2:0] HSIZE,
    input      [31:0] HWDATA,
    input      [ 3:0] HWSTRB,
    input             HREADY,
    output reg [31:0] HRDATA,
    output            HREADYOUT,
    output            HRESP
);

    localparam WORDS = MEM_SIZE_BYTES / 4;
    localparam ADDR_BITS = (WORDS > 1) ? $clog2(WORDS) : 1;

    // Relative address decoding from BASE_ADDR
    wire [31:0] rel_addr = HADDR - BASE_ADDR;
    wire [ADDR_BITS-1:0] word_addr = rel_addr[ADDR_BITS+1:2];

`ifdef ALTERA_RESERVED_QIS
    `define INFER_BYTE_RAM_M9K
`elsif SYNTHESIS
    `define INFER_BYTE_RAM_M9K
`endif

`ifdef INFER_BYTE_RAM_M9K
    // 4 independent 8-bit RAM arrays: Guarantees 100% native M9K Block RAM inference
    // in Intel Quartus Prime without consuming hundreds of thousands of Logic Elements.
    (* ramstyle = "M9K" *) reg [7:0] mem0 [0:WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem1 [0:WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem2 [0:WORDS-1];
    (* ramstyle = "M9K" *) reg [7:0] mem3 [0:WORDS-1];
`else
    // 32-bit memory array with byte enables (directly accessible by testbench preloads)
    reg [31:0] mem [0:WORDS-1];
`endif

    // Wait-State Configuration (Runtime Plusarg Support for Simulation)
    reg [31:0] cfg_wait_states = DEFAULT_WAIT_STATES;
    reg        cfg_random_wait = 1'b0;

    // synthesis translate_off
    initial begin
        if ($test$plusargs("AHB_WAIT_RANDOM")) begin
            cfg_random_wait = 1'b1;
            $display("[AHB_RAM] Wait-state testing: PSEUDO-RANDOM (0 to 4 wait cycles per access)");
        end else if ($value$plusargs("AHB_WAIT_STATES=%d", cfg_wait_states)) begin
            $display("[AHB_RAM] Wait-state testing: FIXED %0d wait cycle(s) per access", cfg_wait_states);
        end
    end
    // synthesis translate_on

    // 16-bit Galois Pseudo-Random Number Generator (LFSR)
    reg [15:0] lfsr;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            lfsr <= 16'hACE1;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // Number of wait states to insert for the next incoming transfer
    wire [2:0] next_wait_cycles = cfg_random_wait ? (lfsr[2:0] % 3'd5) : cfg_wait_states[2:0];

    // Pipeline Registers for Data Phase
    reg [ADDR_BITS-1:0] wr_addr_reg;
    reg                 data_write;
    reg                 data_active;
    reg [2:0]           wait_counter;

    wire req_address_phase = HSEL && HREADY && (HTRANS == 2'b10 || HTRANS == 2'b11);

    // HREADYOUT is 0 while active transfer is waiting, 1 when wait completes or idle
    assign HREADYOUT = (data_active && (wait_counter > 0)) ? 1'b0 : 1'b1;
    assign HRESP     = 1'b0; // OKAY

    // Data Phase Tracking & Wait State Countdown
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            wr_addr_reg  <= {ADDR_BITS{1'b0}};
            data_write   <= 1'b0;
            data_active  <= 1'b0;
            wait_counter <= 3'd0;
        end else begin
            if (data_active && (wait_counter > 0)) begin
                // Decrement wait state countdown
                wait_counter <= wait_counter - 3'd1;
            end else if (HREADY && req_address_phase) begin
                // Transfer address phase accepted -> enter data phase
                wr_addr_reg  <= word_addr;
                data_write   <= HWRITE;
                data_active  <= 1'b1;
                wait_counter <= next_wait_cycles;
            end else if (HREADY) begin
                // No new transfer requested while bus is ready
                data_active  <= 1'b0;
                data_write   <= 1'b0;
                wait_counter <= 3'd0;
            end
        end
    end

    // Signal used by testbench monitor to detect memory write commit
    wire write_commit = data_write && (HREADYOUT == 1'b1) && HREADY;
    wire write_reg    = write_commit;

`ifdef INFER_BYTE_RAM_M9K
    // Synchronous Write to 4 byte-wide M9K blocks
    always @(posedge HCLK) begin
        if (write_commit) begin
            if (HWSTRB[0]) mem0[wr_addr_reg] <= HWDATA[ 7: 0];
            if (HWSTRB[1]) mem1[wr_addr_reg] <= HWDATA[15: 8];
            if (HWSTRB[2]) mem2[wr_addr_reg] <= HWDATA[23: 16];
            if (HWSTRB[3]) mem3[wr_addr_reg] <= HWDATA[31: 24];
        end
    end

    // Synchronous Read: Registered read from 4 byte-wide M9K blocks
    always @(posedge HCLK) begin
        if (HREADY && req_address_phase && !HWRITE) begin
            HRDATA <= {mem3[word_addr], mem2[word_addr], mem1[word_addr], mem0[word_addr]};
        end
    end
`else
    // Synchronous Write (commits on posedge clock when HREADY is high and transfer is complete)
    always @(posedge HCLK) begin
        if (write_commit) begin
            if (HWSTRB[0]) mem[wr_addr_reg][ 7: 0] <= HWDATA[ 7: 0];
            if (HWSTRB[1]) mem[wr_addr_reg][15: 8] <= HWDATA[15: 8];
            if (HWSTRB[2]) mem[wr_addr_reg][23: 16] <= HWDATA[23: 16];
            if (HWSTRB[3]) mem[wr_addr_reg][31: 24] <= HWDATA[31: 24];
        end
    end

    // Synchronous Read:
    always @(posedge HCLK) begin
        if (HREADY && req_address_phase && !HWRITE) begin
            HRDATA <= mem[word_addr];
        end
    end
`endif

endmodule
