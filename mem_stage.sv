
module MEM_Stage
#(
    ID_WIDTH = 13,
    ADDR_WIDTH = 64,
    DATA_WIDTH = 64,
    STRB_WIDTH = DATA_WIDTH/8
)
(
    input clk,
    input reset,

    input decoded_inst_t inst,
    input [63:0] ex_data,
    input [63:0] ex_data2,
    input is_bubble,

    //TODO: all these are for hazard stage, replace them with mem_busy
    output dcache_valid,
    output write_done,      
    output logic dcache_en,

    output [63:0] mem_ex_rdata,


    // == D$ interface ports
    output logic        dc_en,
    output logic [63:0] dc_in_addr,

    output logic        dc_write_en, // write=1, read=0
    output logic [63:0] dc_in_wdata,
    output logic [ 1:0] dc_in_wlen,  // wlen is log(#bytes), 3 = 64bit write

    input  logic [63:0] dc_out_rdata,
    input  logic        dc_out_rvalid,     //TODO: we should maybe merge rvalid and write_done
    input  logic        dc_out_write_done

);

    logic [63:0] mem_rdata;
    logic [63:0] mem_wr_data; // Write data

    assign dcache_en = (inst.is_load || inst.is_store) && !is_bubble;

    logic [5:0] shift_amt;
    assign shift_amt = {ex_data[2:0], 3'b000};
    logic [63:0] mem_rdata_shifted;

    always_comb begin
        // This case only matters for stores
        case (inst.funct3)
            F3LS_B: mem_wr_data = ex_data2[7:0];
            F3LS_H: mem_wr_data = ex_data2[15:0];
            F3LS_W: mem_wr_data = ex_data2[31:0];
            F3LS_D: mem_wr_data = ex_data2[63:0];
            default: mem_wr_data = ex_data2[63:0];
        endcase

        mem_rdata_shifted = mem_rdata >> shift_amt;
        
        // This only matters for loads
        case (inst.funct3)
            // load signed
            F3LS_B: mem_ex_rdata = { {56{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0] };
            F3LS_H: mem_ex_rdata = { {48{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0] };
            F3LS_W: mem_ex_rdata = { {32{mem_rdata_shifted[31]}}, mem_rdata_shifted[31:0] };
            // load unsigned
            F3LS_BU: mem_ex_rdata = { 56'd0, mem_rdata_shifted[7:0] };
            F3LS_HU: mem_ex_rdata = { 48'd0, mem_rdata_shifted[15:0] };
            F3LS_WU: mem_ex_rdata = { 32'd0, mem_rdata_shifted[31:0] };
            default: mem_ex_rdata = mem_rdata;
        endcase
    end


    // === Wire requests to/from D-Cache
    assign dc_en      = dcache_en;
    assign dc_in_addr = ex_data;

    assign dc_write_en = inst.is_store;
    assign dc_in_wdata = mem_wr_data;
    assign dc_in_wlen  = inst.funct3[1:0]; //is log of number of bytes written (3=>8-byte write)

    assign mem_rdata    = dc_out_rdata;
    assign dcache_valid = dc_out_rvalid;
    assign write_done   = dc_out_write_done;



    // Dummy signals for waveform viewer
    logic is_load;
    logic is_store;
    assign is_load = inst.is_load;
    assign is_store = inst.is_store;


endmodule

