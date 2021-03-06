
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
    input advance, // if instruction is actually moving onward this cycle

    output stall, // if MEM instruction needs more time

    output [63:0] mem_ex_rdata,
    output [63:0] atomic_result,

    output force_pipeline_flush, // requests pipeline to be flushed behind MEM stage

    output tlb_invalidate, // requests TLB entries to be flushed
    //TODO: make this more granular


    //=== Trap inputs/outputs
    input op_trapped,
    output         gen_trap,
    output  [63:0] gen_trap_cause,
    output  [63:0] gen_trap_val,

    // == D$ interface ports
        output logic        dc_en,
        output logic [63:0] dc_in_addr,
        
        output logic        dc_write_en, // write=1, read=0
        output logic [63:0] dc_in_wdata,
        output logic [ 1:0] dc_in_wlen,  // wlen is log(#bytes), 3 = 64bit write

        input  logic [63:0] dc_out_rdata,
        input  logic        dc_out_rvalid,     //TODO: we should maybe merge rvalid and write_done
        input  logic        dc_out_write_done,
        input  logic        dc_out_page_fault // if (rvalid||write_done) && page_fault, ignore the data

);
    logic [63:0] mem_rdata;
    logic [63:0] mem_rdata_shifted;
    logic [63:0] mem_wr_data; // Write data
    logic [5:0] shift_amt;
    logic [1:0] atomic_state;
    logic [63:0] alu_result;
    logic [63:0] load_result;

    assign shift_amt = {ex_data[2:0], 3'b000};
    assign mem_rdata = dc_out_rdata;
    assign mem_rdata_shifted = mem_rdata >> shift_amt;

    assign dc_in_addr = ex_data;
    assign dc_in_wlen = inst.funct3[1:0]; //is log of number of bytes written (3=>8-byte write)


    logic atomic_stall; //this gets set by the atomic state machine, if we're in an atomic op
    assign stall = !is_bubble && !op_trapped &&  (
                            (inst.is_load   && !dc_out_rvalid) || 
                            (inst.is_store  && !dc_out_write_done && atomic_state != 2'b10) ||
                            (inst.is_atomic && atomic_stall)
                        );

    logic dbg_inst_is_load;
    logic dbg_inst_is_store;
    assign dbg_inst_is_load = inst.is_load;
    assign dbg_inst_is_store = inst.is_store;

    //=== Page faults:
    assign gen_trap = (dc_out_rvalid || dc_out_write_done) && dc_out_page_fault;
    always_comb begin
        gen_trap_cause = 0;
        gen_trap_val = 0;
        if (dc_out_page_fault && inst.is_load) begin
            gen_trap_cause = MCAUSE_PAGEFAULT_L;
            gen_trap_val = dc_in_addr; //val is whichever virtual address faulted
        end else if (dc_out_page_fault && inst.is_store) begin
            gen_trap_cause = MCAUSE_PAGEFAULT_S;
            gen_trap_val = dc_in_addr; //val is whichever virtual address faulted
        end
           
        //TODO: actually handle page faults on atomics properly
        if (dc_out_page_fault && inst.is_atomic)
            $error("We never actually implemented atomics to properly handle page faults: TODO");
    end


    //Sfence should clear TLBs, clear the pipeline
    assign force_pipeline_flush = !is_bubble && !op_trapped && inst.is_sfence_vma;
    assign tlb_invalidate =       !is_bubble && !op_trapped && inst.is_sfence_vma;


    always_comb begin
        
        // This case only matters for stores
        case (inst.funct3)
            F3LS_B: mem_wr_data = ex_data2[7:0];
            F3LS_H: mem_wr_data = ex_data2[15:0];
            F3LS_W: mem_wr_data = ex_data2[31:0];
            F3LS_D: mem_wr_data = ex_data2[63:0];
        endcase
        
        // This only matters for loads
        case (inst.funct3)
            // load signed
            F3LS_B: mem_ex_rdata = { {56{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0] };
            F3LS_H: mem_ex_rdata = { {48{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0] };
            F3LS_W: mem_ex_rdata = { {32{mem_rdata_shifted[31]}}, mem_rdata_shifted[31:0] };
            F3LS_D: mem_ex_rdata =  mem_rdata;
            // load unsign
            F3LS_BU: mem_ex_rdata = { 56'd0, mem_rdata_shifted[7:0] };
            F3LS_HU: mem_ex_rdata = { 48'd0, mem_rdata_shifted[15:0] };
            F3LS_WU: mem_ex_rdata = { 32'd0, mem_rdata_shifted[31:0] };
            default: begin
                mem_ex_rdata = 0;
                if(!is_bubble && !op_trapped && inst.is_load)
                    $error("Unexpected funct3 in mem_stage load: %b\n", inst.funct3);
            end
        endcase

        if (inst.is_atomic && !is_bubble && !op_trapped) begin
            if (atomic_state != 2)
                atomic_stall = 1;
            else
                atomic_stall = 0;

            if ((atomic_state == 0 && inst.is_store) || atomic_state == 1)
                dc_write_en = 1;
            else
                dc_write_en = 0;
            
            if ((atomic_state == 0 && inst.is_store) || (atomic_state == 1 && inst.is_swap))
                dc_in_wdata = mem_wr_data;
            else if (atomic_state == 1)
                dc_in_wdata = alu_result;
            else
                dc_in_wdata = 'bx;
            
            if (inst.is_store)
                atomic_result = 0;  // Assuming success on every store for now.
            else if (inst.is_load)
                atomic_result = load_result;
            else
                atomic_result = load_result;

            dc_en = !is_bubble;
        end
        else begin
            atomic_stall = 0;
            dc_write_en = inst.is_store;
            dc_in_wdata = mem_wr_data;
            atomic_result = 'bx;
            dc_en = (inst.is_load || inst.is_store) && !is_bubble && !op_trapped;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            atomic_state <= 0;
        end
        else if (atomic_state == 0) begin
            if (!is_bubble && !op_trapped && inst.is_atomic) begin
                if (dc_out_rvalid) begin
                    // load or binary op
                    load_result <= mem_ex_rdata;
                    if (inst.is_load)
                        atomic_state <= 2;
                    else
                        atomic_state <= 1;
                end
                else if (dc_out_write_done) begin
                    // store
                    atomic_state <= 2;
                end
            end
        end
        else if (atomic_state == 1) begin
            if (dc_out_write_done) begin
                atomic_state <= 2;
            end
        end
        else if (atomic_state == 2'b10) begin
            if (advance == 1) begin
                atomic_state <= 0;
            end
        end
        else if (atomic_state == 3) begin
            atomic_state <= 0;
        end
    end

    Atomic_alu atomic_alu(
        .a(ex_data2),
        .b(load_result),
        .width_32(inst.alu_width_32),
        .alu_op(inst.alu_op),
        .result(alu_result)
    );
endmodule

