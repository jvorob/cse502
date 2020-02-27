
module traffic_control(
//    input if_stall,
    input id_stall,
    input ex_stall,
    input mem_stall,
    input wb_stall,

    // Flush all instructions in the pipeline behind the WB stage
    input flush_before_wb,

//    output if_bubble,       // The prefix represents the pipeline reg that feeds into the stage
    output id_bubble,       // that is identified by the prefix (e.g. mem_ = ex_mem reg).
    output ex_bubble,
    output mem_bubble,
    // output wb_bubble,    // Right now, it doesn't make sense to have wb_bubble.
                            // We can add it back later if necessary.

    output id_wr_en,
    output ex_wr_en,
    output mem_wr_en,
    output wb_wr_en
);
    always_comb begin
        if (flush_before_wb) begin
            // Will turn everything into bubbles.
            // If it's possible for WB to stall, we need to come back and add
            // in some logic to prevent the WB pipe reg from getting a bubble.
            // In the meantime, WB can't stall, so we are ok.

            id_bubble = 1;
            ex_bubble = 1;
            mem_bubble = 1;

            wb_wr_en = 1;
            mem_wr_en = 1;
            ex_wr_en = 1;
            id_wr_en = 1;
        end
        else begin
            wb_wr_en = (wb_stall == 0);
            mem_wr_en = (wb_wr_en == 1) && (mem_stall == 0);
            ex_wr_en = (mem_wr_en == 1) && (ex_stall == 0);
            id_wr_en = (ex_wr_en == 1) && (id_stall == 0);

            // wb_bubble = wb_stall;
            mem_bubble = mem_stall;
            ex_bubble = ex_stall;
            id_bubble = id_stall;
        end
    end
endmodule

