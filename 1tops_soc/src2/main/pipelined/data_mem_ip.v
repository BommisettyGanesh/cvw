module data_mem_ip #(parameter DATA_WIDTH = 32, ADDR_WIDTH = 32, MEM_SIZE = 64)(
	input [2:0] funct3,
	input [1:0] wr_addr_10,
	input			[DATA_WIDTH-1:0] wr_data, data_in,
	output reg	[DATA_WIDTH-1:0] wr_data_in
);

always @(*) begin
	case ({funct3, wr_addr_10})
		5'b010_00, 5'b010_01, 5'b010_10, 5'b010_11: wr_data_in = wr_data;				// sw: Store word
		
		5'b000_00: wr_data_in = {data_in[31: 8], wr_data[ 7: 0]};  						// sb: Store byte
		5'b000_01: wr_data_in = {data_in[31:16], wr_data[ 7: 0], data_in[ 7: 0]};  	// sb: Store byte
		5'b000_10: wr_data_in = {data_in[31:24], wr_data[ 7: 0], data_in[15: 0]};  	// sb: Store byte
		5'b000_11: wr_data_in = {wr_data[ 7: 0], data_in[23: 0]}; 							// sb: Store byte

		5'b001_00: wr_data_in = {data_in[31:16], wr_data[15: 0]}; 							// sh: Store half-word
		5'b001_10: wr_data_in = {wr_data[15: 0], data_in[15: 0]}; 							// sh: Store half-word
		
		default:   wr_data_in = {32{1'bx}};
	endcase
end

endmodule
