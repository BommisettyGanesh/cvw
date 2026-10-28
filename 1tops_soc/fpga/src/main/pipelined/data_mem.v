module data_mem #(parameter DATA_WIDTH = 32, ADDR_WIDTH = 32, MEM_SIZE = 64) (
    input                    clk, wr_en,
    input   [2:0]            funct3,
    input   [ADDR_WIDTH-1:0] wr_addr, wr_data,
    output  [DATA_WIDTH-1:0] rd_data_mem
);

// array of 64 32-bit data
reg [DATA_WIDTH-1:0] data_ram [0:MEM_SIZE-1];

wire [ADDR_WIDTH-1:0] word_addr = {2'b00, wr_addr[DATA_WIDTH-1:2]} % 64;

wire [DATA_WIDTH-1:0] wr_data_in, rd_data_ram;

assign rd_data_ram = data_ram[word_addr];

data_mem_ip d_in	(funct3, wr_addr[1:0], wr_data, rd_data_ram, wr_data_in);
data_mem_op d_out (funct3, wr_addr[1:0], rd_data_ram, rd_data_mem);

always @(posedge clk) begin
	if (wr_en) begin
		data_ram[word_addr] <= wr_data_in;
	end
end

endmodule
