// This holds the pipeline registers

// Instruction Fetch / Instruction Decode (+ Register fetch) register
module if_id_reg(
    input clk,
    input reset,
    input stall,
    input [63:0] in_inst,
    output [63:0] out_inst
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            out_inst <= 0;
        end
        else begin
            if (stall == 0) begin
                out_inst <= in_inst;
            end
        end
    end
endmodule


// Instruction Decode / Execution register
module id_ex_reg(
    input clk,
    input reset,
    input stall,
    output funct3
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            
        end
        else begin
            if (stall == 0) begin
                
            end
        end
    end
endmodule


// Execution / Memory register
module ex_mem_reg(
    input clk,
    input reset,
    input stall,
    input [63:0] in_alu_result,
    output [63:0] out_alu_result
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            out_alu_result <= 0;
        end
        else begin
            if (stall == 0) begin
                out_alu_result <= in_alu_result;
            end
        end
    end
endmodule


// Memory / Write-Back register
module mem_wb_reg(
    input clk,
    input reset,
    input stall,

    input [63:0] in_mem_result,
    input [4:0] in_rd,
    input in_en_rd,

    output [63:0] out_mem_result,
    output [4:0] out_rd,
    output out_en_rd
);
    always_ff @(posedge clk) begin
        if (reset == 1) begin
            out_mem_result <= 0;
            out_rd <= 0;
            out_en_rd <= 0;
        end
        else begin
            if (stall == 0) begin
                out_mem_result <= in_mem_result;
                out_rd <= in_rd;
                out_en_rd <= in_en_rd;
            end
            else begin
                // Not sure if this is necessary.
                // Even if en_rd=1, it would just keep writing to the same register with
                // the same value over and over even with stalls.
                out_en_rd <= 0; 
            end
        end
    end
endmodule

