module data_mem_op #(parameter DATA_WIDTH = 32, ADDR_WIDTH = 32, MEM_SIZE = 64)(
	input [2:0] funct3,
	input [1:0] wr_addr_10,
	input 		[DATA_WIDTH-1:0] data_in,
	output reg	[DATA_WIDTH-1:0] rd_data_mem
);

always @(*) begin
    case ({funct3, wr_addr_10})
		  5'b010_00, 5'b010_01, 5'b010_10, 5'b010_11: rd_data_mem = data_in;	// lw
		  
        5'b000_00: rd_data_mem = {{24{data_in[ 7]}}, data_in[ 7: 0]};   // lb: Load signed byte
        5'b000_01: rd_data_mem = {{24{data_in[15]}}, data_in[15: 8]};   // lb: Load signed byte
        5'b000_10: rd_data_mem = {{24{data_in[23]}}, data_in[23:16]};   // lb: Load signed byte
        5'b000_11: rd_data_mem = {{24{data_in[31]}}, data_in[31:24]};   // lb: Load signed byte

        5'b001_00: rd_data_mem = {{16{data_in[15]}}, data_in[15: 0]};   // lh: Load signed half-word
        5'b001_10: rd_data_mem = {{16{data_in[31]}}, data_in[31:16]};   // lh: Load signed half-word

        5'b100_00: rd_data_mem = {24'b0, data_in[ 7: 0]};               // lbu: Load unsigned byte
        5'b100_01: rd_data_mem = {24'b0, data_in[15: 8]};               // lbu: Load unsigned byte
        5'b100_10: rd_data_mem = {24'b0, data_in[23:16]};               // lbu: Load unsigned byte
        5'b100_11: rd_data_mem = {24'b0, data_in[31:24]};               // lbu: Load unsigned byte

        5'b101_00: rd_data_mem = {16'b0, data_in[15:0]};                // lhu: Load unsigned half-word
        5'b101_10: rd_data_mem = {16'b0, data_in[31:16]};               // lhu: Load unsigned half-word

		  default:   rd_data_mem = {32{1'bx}};
    endcase
end
	
endmodule
