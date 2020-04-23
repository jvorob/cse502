
module wb_stage
(
	input clk,
	input reset,
	
	input [63:0] a0,
	input [63:0] a1,
	input [63:0] a2,
	input [63:0] a3,
	input [63:0] a4,
	input [63:0] a5,
	input [63:0] a6,
	input [63:0] a7,

	input is_bubble,

	input [63:0] alu_result,
	input [63:0] mem_result,
	input decoded_inst_t inst,	// instruction in WB stage

	output logic [63:0] result,
	output [4:0] rd,
	output en_rd,

	output logic stall
);
	logic [63:0] ecall_result;
	logic has_ecall_executed;

	assign rd = inst.rd;
	assign en_rd = inst.en_rd;

	always_comb begin
		if (inst.is_load || inst.is_store || inst.is_csr || inst.is_atomic) begin
			result = mem_result;
		end
		else if (inst.is_ecall) begin
			result = ecall_result;
		end
		else begin
			result = alu_result;
		end
	end

    //   // ==== Stall while we're busy executing an ECALL hack (TODO TEMP)
	//   always_comb begin
	//   	if (inst.is_ecall && !is_bubble && !has_ecall_executed) begin
	//   		stall = 1;
	//   	end
	//   	else begin
	//   		stall = 0;
	//   	end
	//   end

    //   // Currently we are flushing everything before WB while WB contains
    //   // an ecall instruction. Might be able to modify it to flush when
    //   // has_ecall_executed == 1.

	//   always_ff @(posedge clk) begin
	//   	if (reset) begin
	//   		has_ecall_executed <= 0;
	//   	end
	//   	else if (is_bubble || !inst.is_ecall || has_ecall_executed) begin
	//   		has_ecall_executed <= 0;
	//   	end
	//   	else if (inst.is_ecall && !is_bubble && !has_ecall_executed) begin
	//   		do_ecall(a7, a0, a1, a2, a3, a4, a5, a6, ecall_result);
	//   		has_ecall_executed <= 1;
	//   	end
	//   end


    // dummy signals to view in waveform
    logic is_ecall;
    assign is_ecall = inst.is_ecall;
endmodule

