
module traffic_control(
    input if_stall,
    input id_stall,
    input ex_stall,
    input mem_stall,
    input wb_stall,

    // Flush all instructions in the pipeline behind the WB stage
    input flush_before_wb,
	input flush_before_ex,

    // If stage_wr_en is also high, causes that stage to clock in a bubble (no instruction)
    output id_gen_bubble,
    output ex_gen_bubble,
    output mem_gen_bubble,
    output wb_gen_bubble,

    output if_wr_en,
    output id_wr_en,
    output ex_wr_en,
    output mem_wr_en,
    output wb_wr_en
);
    always_comb begin
        wb_wr_en = (wb_stall == 0);
        mem_wr_en = (wb_wr_en == 1) && (mem_stall == 0);
        ex_wr_en = (mem_wr_en == 1) && (ex_stall == 0);
        id_wr_en = (ex_wr_en == 1) && (id_stall == 0);

        // IF can advance either through normal pipeline
        // or in case of a jump/pipeline-flush
        if_wr_en = ((id_wr_en == 1) && (if_stall == 0)) ||
                   (flush_before_wb || flush_before_ex); //in this case, IF_next_pc will also be changed

        wb_gen_bubble = mem_stall;
        mem_gen_bubble = ex_stall;
        ex_gen_bubble = id_stall;
        id_gen_bubble = if_stall;

		if (flush_before_wb) begin
            //NOTE: wb currently stalls for one cycle on ecall, due to the ecall fakeos hack
            //if (wb_stall)
            //    $error("Traffic control: WB stage shouldn't be able to stall");

            id_gen_bubble = 1;
            ex_gen_bubble = 1;
            mem_gen_bubble = 1;
            wb_gen_bubble = 1; //we're dumping contents of MEM_stage, so on next cycle WB will inherit MEM's bubble

            id_wr_en = 1;
            ex_wr_en = 1;
            mem_wr_en = 1;
            // if wb_wr_en is set, it will inherit the bubble. Otherwise it can stall as normal
        end
		else if (flush_before_ex) begin
            // next contents of ID and EX registers, if any, will be bubbles
            // (dump them)
            id_gen_bubble = 1;
            ex_gen_bubble = 1;

			id_wr_en = 1;  // ID gets dumped even if stalled
            // EX will be cleared, but it's currently holding the jump
            // EX may stall, so don't wr_en until it can advance normally
            // jump will re-execute continuously as long as it's stalled
        end
    end
endmodule

