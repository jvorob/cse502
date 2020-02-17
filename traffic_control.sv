
module traffic_control(
    input clk,
    input reset,
    
    input if_stall,
    input id_stall,
    input ex_stall,
    input mem_stall,
    input wb_stall,

    output if_bubble,       // The prefix represents the pipeline reg that feeds into the stage
    output id_bubble,       // that is identified by the prefix (e.g. mem_ = ex_mem reg).
    output ex_bubble,
    output mem_bubble,
    output wb_bubble,

    output id_wr_en,
    output ex_wr_en,
    output mem_wr_en,
    output wb_wr_en
);

    always_comb begin
        if (mem_stall == 0) begin
            mem_wr_en = 1;
        end
        if (wb_stall == 0) begin
            wb_wr_en = 1;
        end
    end

    always_comb begin
        if (id_stall == 1) begin
            ex_bubble = 1;
        end
        if (ex_stall == 1) begin
            mem_bubble = 1;
        end
        if (mem_stall == 1) begin
            wb_bubble = 1;
        end
    end



endmodule

