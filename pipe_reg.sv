// This holds the pipeline registers





// Instruction Fetch / Instruction Decode (+ Register fetch) register
module ID_reg(
    // Reg signals
    input clk,
    input reset,
    input stall,

    // Data signals coming in from IF
    input [63:0] next_pc,
    input [63:0] next_inst,

    // Data signals for current ID step
    output [63:0] curr_pc, //instruction not yet decoded, so pass this in separately
    output [63:0] curr_inst
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            //out_inst <= 0;
        end
        else begin
            if (stall == 0) begin
                curr_pc <= next_pc;
                //out_inst <= in_inst;
            end
        end
    end
endmodule


// Instruction Decode / Execution register
module EX_reg(
    // Reg Signals
    input clk,
    input reset,
    input stall,

    // Data signals coming in from ID (decode/regfile)
    input [63:0] next_pc,
    input decoded_inst_t next_deco, // includes pc & immed
    input [63:0]         next_val_rs1,
    input [63:0]         next_val_rs2,


    // Data signals for current EX step
    output [63:0] curr_pc,
    output decoded_inst_t curr_deco,
    output [63:0]         curr_val_rs1,
    output [63:0]         curr_val_rs2
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            
        end
        else begin
            if (stall == 0) begin
                curr_pc <= next_pc;
                
            end
        end
    end
endmodule


// Execution / Memory register
module MEM_reg(
    // Reg Signals
    input clk,
    input reset,
    input stall,

    // Data signals coming in from EX
    input [63:0] next_pc,
    input decoded_inst_t next_deco, // includes pc & immed
    input [63:0]         next_data,  // result from ALU or other primary value
    input [63:0]         next_data2, // extra value if needed (e.g. for stores, etc)


    // Data signals for current MEM step
    output [63:0] curr_pc,
    output decoded_inst_t curr_deco,
    output [63:0]         curr_data,
    output [63:0]         curr_data2
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            //out_alu_result <= 0;
        end
        else begin
            if (stall == 0) begin
                curr_pc <= next_pc;
                //out_alu_result <= in_alu_result;
            end
        end
    end
endmodule


// Memory / Write-Back register
module WB_reg(
    // Reg Signals
    input clk,
    input reset,
    input stall,

    // Data signals coming in from MEM
    input [63:0] next_pc,
    input decoded_inst_t next_deco, // includes pc & immed
    input [63:0]         next_alu_result,
    input [63:0]         next_mem_result,


    // Data signals for current WB step
    output [63:0] curr_pc,
    output decoded_inst_t curr_deco, // includes pc & immed
    output [63:0]         curr_alu_result,
    output [63:0]         curr_mem_result


);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            //out_mem_result <= 0;
            //out_rd <= 0;
            //out_en_rd <= 0;
        end
        else begin
            if (stall == 0) begin
                curr_pc <= next_pc;
                //out_mem_result <= in_mem_result;
                //out_rd <= in_rd;
                //out_en_rd <= in_en_rd;
            end
            else begin
                // Not sure if this is necessary.
                // Even if en_rd=1, it would just keep writing to the same register with
                // the same value over and over even with stalls.
                //out_en_rd <= 0; 
            end
        end
    end
endmodule

