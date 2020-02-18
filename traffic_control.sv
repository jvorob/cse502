
module traffic_control(
//    input if_stall,
    input id_stall,
    input ex_stall,
    input mem_stall,
    input wb_stall,

//    output if_bubble,       // The prefix represents the pipeline reg that feeds into the stage
    output id_bubble,       // that is identified by the prefix (e.g. mem_ = ex_mem reg).
    output ex_bubble,
    output mem_bubble,
    output wb_bubble,

    output id_wr_en,
    output ex_wr_en,
    output mem_wr_en,
    output wb_wr_en
);
    assign wb_wr_en = (wb_stall == 0);
    assign mem_wr_en = (wb_wr_en == 1) && (mem_stall == 0);
    assign ex_wr_en = (mem_wr_en == 1) && (ex_stall == 0);
    assign id_wr_en = (ex_wr_en == 1) && (id_stall == 0);

    assign wb_bubble = wb_stall;
    assign mem_bubble = mem_stall;
    assign ex_bubble = ex_stall;
    assign id_bubble = id_stall;

endmodule

