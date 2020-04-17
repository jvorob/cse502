`include "Sysbus.defs"
`include "enums.sv"
`include "decoder.sv"
`include "alu.sv"
`include "regfile.sv"
`include "pipe_reg.sv"
`include "hazard.sv"
`include "memory_system.sv"
`include "mem_stage.sv"
`include "csr.sv"

module top
#(
  ID_WIDTH = 13,
  ADDR_WIDTH = 64,
  DATA_WIDTH = 64,
  STRB_WIDTH = DATA_WIDTH/8
)
(
  input  clk,
         reset,

  // 64-bit addresses of the program entry point and initial stack pointer
  input  [63:0] entry,
  input  [63:0] stackptr,
  input  [63:0] satp,

  // interface to connect to the bus
  output  wire [ID_WIDTH-1:0]    m_axi_awid,
  output  wire [ADDR_WIDTH-1:0]  m_axi_awaddr,
  output  wire [7:0]             m_axi_awlen,
  output  wire [2:0]             m_axi_awsize,
  output  wire [1:0]             m_axi_awburst,
  output  wire                   m_axi_awlock,
  output  wire [3:0]             m_axi_awcache,
  output  wire [2:0]             m_axi_awprot,
  output  wire                   m_axi_awvalid,
  input   wire                   m_axi_awready,
  output  wire [DATA_WIDTH-1:0]  m_axi_wdata,
  output  wire [STRB_WIDTH-1:0]  m_axi_wstrb,
  output  wire                   m_axi_wlast,
  output  wire                   m_axi_wvalid,
  input   wire                   m_axi_wready,
  input   wire [ID_WIDTH-1:0]    m_axi_bid,
  input   wire [1:0]             m_axi_bresp,
  input   wire                   m_axi_bvalid,
  output  wire                   m_axi_bready,
  output  wire [ID_WIDTH-1:0]    m_axi_arid,
  output  wire [ADDR_WIDTH-1:0]  m_axi_araddr,
  output  wire [7:0]             m_axi_arlen,
  output  wire [2:0]             m_axi_arsize,
  output  wire [1:0]             m_axi_arburst,
  output  wire                   m_axi_arlock,
  output  wire [3:0]             m_axi_arcache,
  output  wire [2:0]             m_axi_arprot,
  output  wire                   m_axi_arvalid,
  input   wire                   m_axi_arready,
  input   wire [ID_WIDTH-1:0]    m_axi_rid,
  input   wire [DATA_WIDTH-1:0]  m_axi_rdata,
  input   wire [1:0]             m_axi_rresp,
  input   wire                   m_axi_rlast,
  input   wire                   m_axi_rvalid,
  output  wire                   m_axi_rready,
  input   wire                   m_axi_acvalid,
  output  wire                   m_axi_acready,
  input   wire [ADDR_WIDTH-1:0]  m_axi_acaddr,
  input   wire [3:0]             m_axi_acsnoop
);

	// This is used to let the instructions in the middle of the pipeline finish
	// executing before we stop. This is because there might still be instructions in the
	// pipeline partially executed after hitting the end of the program with IF_pc.
    logic [2:0] termination_counter;
    

    // Traffic controller signals:
    // gen_bubble
    logic if_gen_bubble;
    logic id_gen_bubble;
    logic ex_gen_bubble;
    logic mem_gen_bubble;
    logic wb_gen_bubble;

    // wr_en
    logic id_wr_en;
    logic ex_wr_en;
    logic mem_wr_en;
    logic wb_wr_en;

	// flush signals
    logic flush_before_wb;	// Used for ecall
	logic flush_before_mem; // Currently used upon satp modification (in case virtual memory is toggled). Can be used for other things.
    logic flush_before_ex;	// Used for jumps/branches

    // csr register values
    logic [63:0] mepc_csr;

    // ------------------------BEGIN IF STAGE--------------------------
    


    logic [63:0] IF_pc;
    logic [31:0] IF_inst;
    logic IF_inst_valid; //if cache output is valid

    // Note: we have if_wr_en to update IF_pc, but that doesn't mean we're
    // executing the instruction currently in IF. That only happens when the
    // instruction currently in IF goes into the pipeline, which happens
    // when ID reg is taking in a fresh instruction
    logic IF_is_executing;
    assign IF_is_executing = id_wr_en && !id_gen_bubble;


    // IF-stage PC logic
    always_ff @ (posedge clk) begin
        if (reset) begin
            $display("satp: %x", satp);
            $display("Entry: %x", entry);
            IF_pc <= entry;
        end 
        
        else if (if_wr_en) begin
            // (ECALL: re-execute flushed instructions
            if (flush_before_wb) begin 
                if(!WB_reg.valid) $error("ERROR: flush_before_wb expects ECALL inst in WB, found bubble");

                // start after ECALL which is in WB (TODO: will be in WB?)
                IF_pc <= WB_reg.curr_pc + 4;
            end

            else if (flush_before_mem) begin
                if (!MEM_reg.valid) $error ("ERROR: flush_before_mem expects inst in MEM, found bubble");

                // start after instruction in MEM
                IF_pc <= MEM_reg.curr_pc + 4;
            end

            // (JUMP: change pc to jump_target)
            else if (flush_before_ex) begin 
                if(!EX_reg.valid) $error("ERROR: flush_before_ex expects inst in EX, found bubble");

                if (do_jump) 
                    IF_pc <= jump_target_address;
                else 
                    $error("ERROR: We should only flush_before_ex if do_jump is high"); 
            end

            // Default PC logic: advance:  
            else begin
                IF_pc <= IF_pc+4;
            end
        end
    end

    // ==== send I$ requests into memory system
    logic [63:0] mem_sys_ic_req_addr; //cant assign directly to input of module, so do this instead
    assign mem_sys_ic_req_addr = (IF_pc);
    assign IF_inst_valid = (mem_sys.ic_resp_valid);
    assign IF_inst =       (mem_sys.ic_resp_inst);

    // ------------------------END IF STAGE----------------------------

    ID_reg ID_reg(
        .clk,
        .reset,

        //traffic signals
        .wr_en(id_wr_en),
        .gen_bubble(id_gen_bubble),
        .valid(),

        // incoming signals for next step's ID
        .next_pc(IF_pc),
        .next_inst(IF_inst),

        // outgoing signals for current ID stage
        .curr_pc(),
        .curr_inst()
    );

    // ------------------------BEGIN ID STAGE--------------------------

    // Components decoded from IF_inst, set by decoder
    decoded_inst_t ID_deco; 

    Decoder d(
        .inst(ID_reg.curr_inst),
        .valid(ID_reg.valid),
        .pc(ID_reg.curr_pc),
        .out(ID_deco)
    );
    
    // Register file
    logic [63:0] ID_out1;
    logic [63:0] ID_out2;

    // Ecall values
    logic [63:0] a0, a1, a2, a3, a4, a5, a6, a7;

    // === Enable RegFile writeback USING SIGNALS FROM WB STAGE
    logic writeback_en; // enables writeback to regfile
	logic [63:0] WB_result;
	logic [4:0] WB_rd;
	logic WB_en_rd;
    assign writeback_en = WB_reg.valid && !haz_wb_stall && WB_en_rd; 
    // only wb on a valid instruction, not stalled (i.e. completed)
    // and which actually has something to writeback (en_rd)

    RegFile rf(
        .clk(clk),
        .reset(reset),
        .stackptr(stackptr),

        .read_addr1(ID_deco.rs1),
        .read_addr2(ID_deco.rs2),

        .wb_addr(WB_rd),
        .wb_data(WB_result),
        .wb_en(writeback_en),

        .out1(ID_out1),
        .out2(ID_out2),

        .a0(a0), .a1(a1), .a2(a2), .a3(a3), .a4(a4), .a5(a5), .a6(a6), .a7(a7)
    );

    //== Some dummy signals for debugging (since gtkwave can't show packed structs
    logic [63:0] ID_immed = ID_deco.immed;
    logic [4:0] ID_rd = ID_deco.rd;
    
    // -----------------------END ID STAGE------------------------------

    EX_reg EX_reg(
        .clk,
        .reset,

        //traffic signals
        .wr_en(ex_wr_en),
        .gen_bubble(!ID_reg.valid || ex_gen_bubble),
        .valid(),

        // Data coming in from ID + RF stage
        .next_pc(ID_reg.curr_pc),
        .next_deco(ID_deco), // includes pc & immed
        .next_val_rs1(ID_out1),
        .next_val_rs2(ID_out2),


        // Data signals for current EX step
        .curr_pc(),
        .curr_deco(),
        .curr_val_rs1(),
        .curr_val_rs2()
    );

    // -----------------------BEGIN EX STAGE----------------------------

    decoded_inst_t EX_deco;
    assign EX_deco = EX_reg.curr_deco;

    // == ALU signals
    logic [63:0] alu_out;
    logic [63:0] alu_b_input;

    // ALU either gets value of immed or value of rs2
    assign alu_b_input = (EX_deco.alu_use_immed ? 
            EX_deco.immed : 
            EX_reg.curr_val_rs2);

    Alu a(
        .a(EX_reg.curr_val_rs1),
        .b(alu_b_input),
        .funct3  (EX_deco.funct3),
        .funct7  (EX_deco.funct7),
        .width_32(EX_deco.alu_width_32),
        .is_load(EX_deco.is_load),
        .is_store(EX_deco.is_store),
        .is_atomic(EX_deco.is_atomic),

        .result(alu_out)
    );

    // Jump logic
    logic [63:0] jump_target_address;
    logic do_jump;

    logic debug_is_mret;
    assign debug_is_mret = EX_deco.is_mret;
    always_comb begin
        if (EX_deco.is_mret) begin
            // mepc
            jump_target_address = mepc_csr & ~64'b011;
        end
        else begin
            // mask off bottommost bit of jump target: (according to RISCV spec)
            jump_target_address = (EX_deco.jump_absolute ? alu_out : (EX_reg.curr_pc + EX_deco.immed)) & ~64'b1;
        end
    end


    //Deciding whether to jump
    always_comb begin
        case (EX_deco.jump_if) inside
			JUMP_NO:		do_jump = 0;
			JUMP_YES:		do_jump = 1;
			JUMP_ALU_EQZ:	do_jump = (alu_out == 0);
			JUMP_ALU_NEZ:	do_jump = (alu_out != 0);
        endcase
		
        if (termination_counter != 1) begin
    		flush_before_ex = do_jump;
        end
        else begin
            flush_before_ex = 0;
        end
    end


    logic [63:0] exec_result;

    logic ex_keep_pc_plus_immed = EX_deco.keep_pc_plus_immed;

    //Deciding EXEC_stage output
    always_comb begin
        if (do_jump) begin // Jumps store return addr (pc+4)
            exec_result = EX_reg.curr_pc + 4 ; //(For JAL/JALR. Branches will discard it anyway)

        end else if (EX_deco.keep_pc_plus_immed) begin //FOR AUIPC
            exec_result = EX_reg.curr_pc + EX_deco.immed;

        end else if (EX_deco.alu_nop) begin
            exec_result = EX_reg.curr_val_rs1;
        end else begin //All others
            exec_result = alu_out;
        end
    end


    //== Some dummy signals for debugging (since gtkwave can't show packed structs
    logic [63:0] EX_immed = EX_deco.immed;
    logic [4:0] EX_rs1 = EX_deco.rs1;
    logic [4:0] EX_rs2 = EX_deco.rs2;

    // ------------------------END EX STAGE-----------------------------

    MEM_reg MEM_reg(
        .clk(clk),
        .reset(reset),
        
        //traffic signals
        .wr_en(mem_wr_en),
        .gen_bubble(!EX_reg.valid || mem_gen_bubble),
        .valid(),

        // Data coming in from EX
        .next_pc(EX_reg.curr_pc),
        .next_deco(EX_deco), // includes pc & immed
        .next_data(exec_result),  // result from ALU or other primary value
        .next_data2(EX_reg.curr_val_rs2), // extra value if needed (e.g. for stores, etc)

        // Data signals for current MEM step
        .curr_pc(),
        .curr_deco(),
        .curr_data(),
        .curr_data2(),

        .next_do_jump(do_jump),
        .next_jump_target(jump_target_address),
        .curr_do_jump(),
        .curr_jump_target()
    );

    // ------------------------BEGIN MEM STAGE--------------------------

    logic [63:0] mem_ex_rdata;   // Properly extended rdata
    logic [63:0] atomic_result;

    logic [63:0] csr_rs1_val;
    logic [63:0] csr_result;
    logic [63:0] mem_stage_result;

    assign csr_rs1_val = (MEM_reg.curr_deco.csr_immed) ? MEM_reg.curr_deco.rs1 : MEM_reg.curr_data;
    assign mem_stage_result = (MEM_reg.curr_deco.is_csr) ? csr_result :
                              (MEM_reg.curr_deco.is_atomic) ? atomic_result : mem_ex_rdata;

    Control_Status_Reg CSRs(
        .clk,
        .reset,

        .addr(MEM_reg.curr_deco.immed),
        .val(csr_rs1_val),

        .valid(MEM_reg.valid),
        .is_csr(MEM_reg.curr_deco.is_csr),
        .csr_rw(MEM_reg.curr_deco.csr_rw),
        .csr_rs(MEM_reg.curr_deco.csr_rs),
        .csr_rc(MEM_reg.curr_deco.csr_rc),
         
        .csr_result(csr_result),
        .mepc_csr,
        
        .modifying_satp(flush_before_mem)
    );

    MEM_Stage mem_stage(
        .clk,
        .reset,

        .inst(MEM_reg.curr_deco),
        .ex_data(MEM_reg.curr_data),
        .ex_data2(MEM_reg.curr_data2),
        .is_bubble(!MEM_reg.valid),
        .advance(mem_wr_en),
        
        .mem_ex_rdata(mem_ex_rdata),
        .atomic_stall(),
        .atomic_result,

        // === D$ interface (passed to MemorySystem)
        .dc_en            (),  // input ports get read in at MemorySystem instantiation
        .dc_in_addr       (),  // since you can't assign directly to an input port
        .dc_write_en      (),
        .dc_in_wdata      (),
        .dc_in_wlen       (),
        .dc_out_rdata     (mem_sys.dc_out_rdata),
        .dc_out_rvalid    (mem_sys.dc_out_rvalid),
        .dc_out_write_done(mem_sys.dc_out_write_done)
    );

    // ------------------------END MEM STAGE----------------------------

    WB_reg WB_reg(
        .clk(clk),
        .reset(reset),

        //traffic signals
        .wr_en(wb_wr_en),
        .gen_bubble(!MEM_reg.valid || wb_gen_bubble),
        .valid(),

        // Data signals coming in from MEM
        .next_pc(MEM_reg.curr_pc),
        .next_deco(MEM_reg.curr_deco),
        .next_alu_result(MEM_reg.curr_data),
        .next_mem_result(mem_stage_result),

        // Data signals for current WB step
        .curr_pc(),
        .curr_deco(),
        .curr_alu_result(),
        .curr_mem_result(),

        .next_do_jump(MEM_reg.curr_do_jump),
        .next_jump_target(MEM_reg.curr_jump_target),
        .curr_do_jump(),
        .curr_jump_target()
    );

    // ------------------------BEGIN WB STAGE---------------------------

	logic ecall_stall;

	wb_stage wb(
		.clk(clk),
		.reset(reset),
		
		.a0(a0),
		.a1(a1),
		.a2(a2),
		.a3(a3),
		.a4(a4),
		.a5(a5),
		.a6(a6),
		.a7(a7),
		
		.is_bubble(!WB_reg.valid),

		.alu_result(WB_reg.curr_alu_result),
		.mem_result(WB_reg.curr_mem_result),
		.inst(WB_reg.curr_deco),
		
		.result(WB_result),
		.rd(WB_rd),
		.en_rd(WB_en_rd),

		.ecall_stall(ecall_stall)
	);

    always_comb begin
        if (WB_reg.valid && !ecall_stall && WB_reg.curr_do_jump) begin
            $display("jump to %x, from %x", WB_reg.curr_jump_target, WB_reg.curr_pc);
        end
    end

    // ------------------------END WB STAGE-----------------------------
    
    // -------Modules outside of pipeline (e.g. hazard detection)-------
    
    logic haz_id_stall;
    logic haz_ex_stall;
    logic haz_mem_stall;
    logic haz_wb_stall;
    
    hazard_unit haz(
        .ID_deco(ID_deco),
        .EX_deco(EX_deco),
        .MEM_deco(MEM_reg.curr_deco),
        .WB_deco(WB_reg.curr_deco),

        .id_valid (ID_reg.valid),
        .ex_valid (EX_reg.valid),
        .mem_valid(MEM_reg.valid),
        .wb_valid (WB_reg.valid),

        //Mem signals (TODO: refactor these away)
		.dcache_valid(mem_sys.dc_out_rvalid),
		.write_done(mem_sys.dc_out_write_done),
		.dcache_enable(mem_stage.dc_en),

        // WB signals (TODO refactor these away)
		.ecall_stall(ecall_stall),
        .wb_is_ecall(WB_reg.curr_deco.is_ecall),
        .flush_before_wb(flush_before_wb),

        // Outputs stalls at corresponding locations
        .id_stall(haz_id_stall),
        .ex_stall(haz_ex_stall),
        .mem_stall(haz_mem_stall),
        .wb_stall(haz_wb_stall)
    );

    traffic_control traffic(
        // Inputs (stalls from hazard unit)
        .if_stall(!IF_inst_valid), //IF doesn't get data dependencies, stalls on Icache
        .id_stall(haz_id_stall),
        .ex_stall(haz_ex_stall),
        .mem_stall(haz_mem_stall || mem_stage.atomic_stall),
        .wb_stall(haz_wb_stall),

        // Whether that reg is actuall holding anything at the moment
        .id_valid (ID_reg.valid),
        .ex_valid (EX_reg.valid),
        .mem_valid(MEM_reg.valid),
        .wb_valid (WB_reg.valid),

        .flush_before_wb(flush_before_wb),
        .flush_before_mem(flush_before_mem),
		.flush_before_ex(flush_before_ex),

        // Output gen bubbles
        // IF should never get a bubble, we always have some intruction we're trying to fetch
        .id_gen_bubble(id_gen_bubble),
        .ex_gen_bubble(ex_gen_bubble),
        .mem_gen_bubble(mem_gen_bubble),
        .wb_gen_bubble(wb_gen_bubble),

        // Output wr_en
        .if_wr_en(if_wr_en),
        .id_wr_en(id_wr_en),
        .ex_wr_en(ex_wr_en),
        .mem_wr_en(mem_wr_en),
        .wb_wr_en(wb_wr_en)
    );

    logic vm_en;
    always_comb begin
        if (CSRs.satp_csr[63:60] == 9) begin
            $display("Turning on VM");
            vm_en = 1;
        end
        else
            vm_en = 0;
    end

    // ===== Icache and Dcache access is all routed into here
    MemorySystem #( ID_WIDTH, ADDR_WIDTH, DATA_WIDTH, STRB_WIDTH) mem_sys(
        .clk,
        .reset,
        .satp,    //TODO: for now is value from HAVETLB, later will be from CSR
        .virtual_en(vm_en),  //leave virtual memory disabled for now

        //I$ ports
        .ic_req_addr(mem_sys_ic_req_addr),  // this is assigned from a signal since it's an input
        .ic_en(1), // TODO: will we ever need to disable the I$?
        .ic_resp_inst(), .ic_resp_valid(),  // these can be read as mem_sys.xxx, since theyre outputs

        //D$ ports
        .dc_en      (mem_stage.dc_en), 
        .dc_in_addr (mem_stage.dc_in_addr),
        .dc_write_en(mem_stage.dc_write_en), // write=1, read=0
        .dc_in_wdata(mem_stage.dc_in_wdata),
        .dc_in_wlen (mem_stage.dc_in_wlen),  // wlen is log(#bytes), 3 = 64bit write

        .dc_out_rdata(), .dc_out_rvalid(), .dc_out_write_done(),

        .* //slurp all the AXI ports it needs
    );



    always_ff @ (posedge clk) begin //Assert intructions aligned
        if (IF_pc[1:0] != 2'b00) 
            $error("ERROR: executing unaligned instruction at IF_pc=%x", IF_pc);
    end

    // ==== Termination counter logic:
    always_ff @ (posedge clk) begin
        if (reset) 
            termination_counter <= 0;
        else if (IF_is_executing && IF_inst != 0) // Count resets for each real inst
            termination_counter <= 0;

        else if (IF_is_executing && IF_inst == 0) begin // Count advances for each null inst
            termination_counter <= termination_counter + 1;

            if (termination_counter == 5) begin
                $display("===== Program terminated =====");
                $display("    IF_pc = 0x%0x", IF_pc);
                    for(int i = 0; i < 32; i++)
                    $display("    r%2.2d: %10d (0x%x)", i, rf.regs[i], rf.regs[i]);
                $finish;
            end

        end
    end

    initial begin
            $display("Initializing top, entry point = 0x%x", entry);
    end
endmodule
