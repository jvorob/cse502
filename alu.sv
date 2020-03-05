
module Alu
(
    input [63:0] a,             // rs1
    input [63:0] b,             // rs2 or immediate
    input [2:0] funct3,
    input [6:0] funct7,

    // Instead of OP: we only need to specify control lines
    input width_32, //set for OP_32 instructions
    input [6:0] op,

    input is_load,
    input is_store,
	input is_jump,
	input is_branch,
	input add_operation,

    output [63:0] result
);

    logic [127:0] product;

    // signed signals
    logic signed [63:0] a_sig;
    logic signed [63:0] b_sig;
    logic signed [127:0] product_sig;

    assign a_sig = a;
    assign b_sig = b;
    assign product_sig = product;

    always_comb begin

		if (add_operation) begin
			result = a + b;
		end
		else if (is_jump) begin
			result = a + b;
		end
		else if (is_branch) begin
			case (funct3) inside
				F3B_BEQ, F3B_BNE: result = a + b;
				F3B_BLT, F3B_BGE: result = (a_sig < b_sig) ? 1 : 0;
				F3B_BLTU, F3B_BGEU: result = a < b ? 1 : 0;
				default: begin
					result = 0;
					$display("ERROR: Invalid branch funct3");
				end
			endcase
		end
		else if (is_load || is_store) begin
            result = a + b;
        end
        else if (!width_32) begin
            case (funct7) inside

                // ===== Normal ALU OPs
                7'b0?0_0000: begin   // bit 6 sets subtract (for addsub) or arithmetic (for shift right)
                    case (funct3) inside
                        F3OP_ADD_SUB: begin
                            if (funct7[5]) begin //SUB
                                result = a - b;
                            end else begin //ADD
                                result = a + b;
                            end
                        end
                        F3OP_SLL:  result = a << b[5:0];
                        F3OP_SLT:  result = (a_sig < b_sig) ? 1 : 0;
                        F3OP_SLTU: result = a < b ? 1 : 0;
                        F3OP_XOR:  result = a ^ b;
                        F3OP_SRX: begin
                            if (funct7[5]) //SRA
                                result = a >>> b[5:0]; // >>> is arithmetic shift
                            else //SRL
                                result = a >> b[5:0];
                        end
                        F3OP_OR: result = a | b;
                        F3OP_AND: result = a & b;

                        default: begin
                            result = 64'hDEADBEEF;
                            $error("Invalid OP in ALU");
                        end
                    endcase
                end

                // ==== Multiply OPs
                7'b000_0001: begin
                    case (funct3) inside
                        F3M_MUL: result = a_sig * b_sig;
                        
                        F3M_MULH: begin
                            product = a_sig * b_sig;
                            result = product[127:64];
                        end
                        
                        F3M_MULHSU: begin
                            product = a_sig * b;
                            result = product[127:64];
                        end

                        F3M_MULHU: begin
                            product = a * b;
                            result = product[127:64];
                        end
                        
                        F3M_DIV: result = a_sig / b_sig;
                        F3M_DIVU: result = a / b;
                        F3M_REM:  result = a_sig % b_sig;
                        F3M_REMU: result = a % b;
                        
                        default: begin
                            result = 64'hDEADBEEF;
                            $error("Invalid MUL OP in ALU");
                        end
                    endcase
                end
            endcase


            // =============================================
            //               32-BIT wide ops
            //
        end
		else begin // width_32 == 1
            case (funct7) inside

                // === 32-bit Normal OPs
                7'b0?0_0000: begin   // bit 6 sets subtract (for addsub) or arithmetic (for shift right)
                    // The only -W ops that aren't multiply are ADD/SUB, SLL, SRA, and SRL

                    Funct3_Op f3op_code = funct3;
                    case (f3op_code) inside
                        F3OP_ADD_SUB: begin
                            if (funct7[5]) begin //SUBW
                                product = a_sig - b_sig;
                                result = { { 32{product[31]} }, product[31:0]};
                            end else begin //ADDW
                                product = a_sig + b_sig;
                                result = { { 32{product[31]} }, product[31:0]};
                            end
                        end
                        F3OP_SLL: begin
                            product = a[31:0] << b[4:0];
                            result = { { 32{ product[31] } }, product[31:0]};
                        end
                        F3OP_SRX: begin
                            if (funct7[5]) begin //SRA
                                product = a[31:0] >>> b[4:0];
                                result = { { 32{ product[31] } }, product[31:0] };
                            end else begin //SRL
                                product = a[31:0] >> b[4:0];
                                result = { { 32{ product[31] } }, product[31:0] };
                            end
                        end
                        default: begin
                            result = 64'hDEADBEEF;
                            $error("ERROR: Invalid funct3 for 32-bit ALU OP: '%b'", funct3);
                        end
                    endcase
                end

                // === 32-bit Multiply OPs
                7'b000_0001: begin
                    case (funct3) inside
                        // These instructions are actually the instructions with the "W" appended at the end
                        // of the instruction names (e.g. MULW, DIVW, ...)
                        F3M_MUL: begin
                            product = a_sig[31:0] * b_sig[31:0];
                            result = { { 32{product[31]} }, product[31:0] };
                        end
                        F3M_DIV: begin
                            product = a_sig[31:0] / b_sig[31:0];
                            result = { { 32{product[31]}  }, product[31:0]};
                        end
                        F3M_DIVU: begin
                            product = a[31:0] / b[31:0];
                            result = { { 32{product[31]} }, product[31:0]};
                        end
                        F3M_REM: begin
                            product = a_sig[31:0] % b_sig[31:0];
                            result = { { 32{product[31]} }, product[31:0]};
                        end
                        F3M_REMU: begin
                            product = a[31:0] % b_sig[31:0];
                            result = { { 32{product[31]} }, product[31:0]};
                        end
                        default: begin
                            result = 64'hDEADBEEF;
                            $error("ERROR: Invalid funct3 for 32bit MUL op, '%b'", funct3);
                        end
                    endcase

                end
    
//    
//            default: begin
//                $display("\n");
//                $display("Decoding instruction %b ", inst);
//    
//                $display("Not recognized instruction.");
//                $display("got opcode %s ('%b\')", op_code.name(), op_code);
//    
//                $display(" I-Immed is %x (%b)", immed_I, immed_I);
//                $display(" S-Immed is %x (%b)", immed_S, immed_S);
//                $display("SB-Immed is %x (%b)", immed_SB, immed_SB);
//                $display(" U-Immed is %x (%b)", immed_U, immed_U);
//                $display("UJ-Immed is %x (%b)", immed_UJ, immed_UJ);
//            end
            endcase
        end //if (!width_32)
    end //always_comb
endmodule

