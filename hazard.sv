// This file holds the hazard detection unit.

module hazard_unit(
    // signals from IF/ID Reg
    input decoded_inst_t ID_deco,
    input id_bubble,

    // signals from ID/EX Reg
    input decoded_inst_t EX_deco,
    input ex_bubble,

    // signals from EX/MEM Reg
    input decoded_inst_t MEM_deco,
    input mem_bubble,

    // signals from MEM/WB Reg
    input decoded_inst_t WB_deco,
    input wb_bubble,

    output id_stall,
    output ex_stall,
    output mem_stall,
    output wb_stall
);
    // ID signals
    logic [4:0] id_rs1, id_rs2;
    logic id_en_rs1, id_en_rs2;

    assign id_rs1 = ID_deco.rs1;
    assign id_rs2 = ID_deco.rs2;
    assign id_en_rs1 = ID_deco.en_rs1;
    assign id_en_rs2 = ID_deco.en_rs2;

    // EX signals
    logic [4:0] ex_rd;
    logic id_en_rd;

    assign ex_rd = EX_deco.rd;
    assign ex_en_rd = EX_deco.en_rd;
    
    // MEM signals 
    logic [4:0] mem_rd;
    logic mem_en_rd;

    assign mem_rd = MEM_deco.rd;
    assign mem_en_rd = MEM_deco.en_rd;
    
    // WB signals
    logic [4:0] wb_rd;
    logic wb_en_rd;

    assign wb_rd = WB_deco.rd;
    assign wb_en_rd = WB_deco.en_rd;

    always_comb begin
        if (id_bubble) begin
            id_stall = 0;
        end
        else begin
            if ( !wb_bubble && wb_en_rd && ((wb_rd == id_rs1 && id_en_rs1) || (wb_rd == id_rs2 && id_en_rs2)) ) begin 
                id_stall = 1;
            end
            else if ( !mem_bubble && mem_en_rd && ((mem_rd == id_rs1 && id_en_rs1) || (mem_rd == id_rs2 && id_en_rs2)) ) begin
                id_stall = 1;
            end
            else if ( !ex_bubble && ex_en_rd && ((ex_rd == id_rs1 && id_en_rs1) || (ex_rd == id_rs2 && id_en_rs2)) ) begin
                id_stall = 1;
            end
            else begin
                id_stall = 0;
            end
        end
    end

    assign ex_stall = 0;
    assign mem_stall = 0;
    assign wb_stall = 0;
endmodule

