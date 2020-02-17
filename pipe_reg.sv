// This holds the pipeline registers


/* 
 * RULES FOR REGISTERS:
 *
 * Each interstage is named after the stage it goes into
 * i.e. ID_reg is the IF/ID interstage
 *
 *
 * Each interstage either holds a valid instruction (data_valid==1)
 * Or it holds a bubble (data_valid==0, all regs cleared)
 *
 * If it holds a valid op which must stay put, then the reg should have
 *    (!input_en, !do_bubble)
 *
 * If its command is a bubble, or an op which can advance, then it needs to
 * take in the value from the preceding stage
 *
 * The op it takes in can be a valid op, in which our reg gets (input_en,  !do_bubble)
 * Or the op it takes in can be a bubble, and we get           (<dontcare>, do_bubble)
 *
 */



// Instruction Fetch / Instruction Decode (+ Register fetch) register
module ID_reg(
    // Control signals
    input clk,
    input reset,

    // Traffic Signals
    input input_en,    // allows reg to clock-in results from prev stage
    input do_bubble,   // clears reg, priority over input_en
    output data_valid, // is 1 for normal ops, 0 for bubbles

    // Data signals coming in from IF
    input [63:0] next_pc,
    input [63:0] next_inst,

    // Data signals for current ID step
    output [63:0] curr_pc, //instruction not yet decoded, so pass this in separately
    output [63:0] curr_inst
);
    always_ff @(posedge clk) begin
        if (reset == 1 || do_bubble == 1) begin
            data_valid <= 0;
            curr_pc    <= 0;
            curr_inst  <= 0;
        end
        else begin
            if (input_en) begin // if clocking in a bubble, do_bubble would have been set
                data_valid <= 1;
                curr_pc    <= next_pc;
                curr_inst  <= next_inst;
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

    // Traffic Signals
    input input_en,    // allows reg to clock-in results from prev stage
    input do_bubble,   // clears reg, priority over input_en
    output data_valid, // is 1 for normal ops, 0 for bubbles

    // Data signals coming in from ID (decode/regfile)
    input [63:0] next_pc,
    input decoded_inst_t next_deco, // includes pc & immed
    input [63:0]         next_val_rs1,
    input [63:0]         next_val_rs2,


    // Data signals for current EX step
    output [63:0]         curr_pc,
    output decoded_inst_t curr_deco,
    output [63:0]         curr_val_rs1,
    output [63:0]         curr_val_rs2
);
    always_ff @(posedge clk) begin
        if (reset == 1 || do_bubble == 1) begin
            data_valid   <= 0;
            curr_pc      <= 0;
            curr_deco    <= 0;
            curr_val_rs1 <= 0;
            curr_val_rs2 <= 0;
        end
        else begin
            if (input_en) begin // if clocking in a bubble, do_bubble would have been set
                data_valid   <= 1;
                curr_pc      <= next_pc;
                curr_deco    <= next_deco;
                curr_val_rs1 <= next_val_rs1;
                curr_val_rs2 <= next_val_rs2;
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

    // Traffic Signals
    input input_en,    // allows reg to clock-in results from prev stage
    input do_bubble,   // clears reg, priority over input_en
    output data_valid, // is 1 for normal ops, 0 for bubbles

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
        if (reset == 1 || do_bubble == 1) begin
            data_valid   <= 0;
            curr_pc      <= 0;
            curr_deco    <= 0;
            curr_data    <= 0;
            curr_data2   <= 0;
        end
        else begin
            if (input_en) begin // if clocking in a bubble, do_bubble would have been set
                data_valid   <= 1;
                curr_pc      <= next_pc;
                curr_deco    <= next_deco;
                curr_data    <= next_data;
                curr_data2   <= next_data2;
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

    // Traffic Signals
    input input_en,    // allows reg to clock-in results from prev stage
    input do_bubble,   // clears reg, priority over input_en
    output data_valid, // is 1 for normal ops, 0 for bubbles

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
        if (reset == 1 || do_bubble == 1) begin
            data_valid      <= 0;
            curr_pc         <= 0;
            curr_deco       <= 0;
            curr_alu_result <= 0;
            curr_mem_result <= 0;
        end
        else begin
            if (input_en) begin // if clocking in a bubble, do_bubble would have been set
                data_valid      <= 1;
                curr_pc         <= next_pc;
                curr_deco       <= next_deco;
                curr_alu_result <= next_alu_result;
                curr_mem_result <= next_mem_result;
            end
        end
    end
endmodule
