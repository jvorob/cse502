// This file holds the hazard detection unit.
//
// Looks at nonlocal interactions between pipeline stages
// (i.e. data dependencies spanning several stages)
// Notifies of data hazards detected
//
// TODO: add forwarding signals (i.e. also output which reg vals
//                               to forward through which stages)
// 

module hazard_unit(
    // Inputs
    input decoded_inst_t ID_deco,
    input decoded_inst_t EX_deco,
    input decoded_inst_t MEM_deco,
    input decoded_inst_t WB_deco,

    input id_valid,
    input ex_valid,
    input mem_valid,
    input wb_valid,

    // Outputs
    output data_hazard_ID
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
    logic ex_en_rd;

    assign ex_rd = EX_deco.rd;
    assign ex_en_rd = EX_deco.en_rd;
    
    // MEM signals 
    logic [4:0] mem_rd;
    logic mem_en_rd;
	logic mem_is_store;
	logic mem_is_load;

    assign mem_rd = MEM_deco.rd;
    assign mem_en_rd = MEM_deco.en_rd;
    assign mem_is_store = MEM_deco.is_store;
	assign mem_is_load = MEM_deco.is_load;

    // WB signals
    logic [4:0] wb_rd;
    logic wb_en_rd;

    assign wb_rd = WB_deco.rd;
    assign wb_en_rd = WB_deco.en_rd;


    // === Detect data hazards in ID stage
    always_comb begin
        if (!id_valid) begin
            data_hazard_ID = 0;
        end
        else begin
            if ( wb_valid && wb_en_rd && ((wb_rd == id_rs1 && id_en_rs1) || (wb_rd == id_rs2 && id_en_rs2)) ) begin 
                data_hazard_ID = 1;
            end
            else if ( mem_valid && mem_en_rd && ((mem_rd == id_rs1 && id_en_rs1) || (mem_rd == id_rs2 && id_en_rs2)) ) begin
                data_hazard_ID = 1;
            end
            else if ( ex_valid && ex_en_rd && ((ex_rd == id_rs1 && id_en_rs1) || (ex_rd == id_rs2 && id_en_rs2)) ) begin
                data_hazard_ID = 1;
            end
            else begin
                data_hazard_ID = 0;
            end
        end
    end

endmodule

