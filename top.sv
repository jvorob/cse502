`include "Sysbus.defs"
`include "enums.sv"
`include "decoder.sv"
`include "alu.sv"
`include "regfile.sv"
`include "pipe_reg.sv"
`include "hazard.sv"
`include "memory_system.sv"
`include "mem_stage.sv"
`include "privilege.sv"

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
  input  [63:0] satp, // TODO: DON'T USE THIS!!! (comes from Mike's hacked satp,  now satp comes from CSR)

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

    // ==== META-Logic and debugging signals

	// This is used to let the instructions in the middle of the pipeline finish
	// executing before we stop. This is because there might still be instructions in the
	// pipeline partially executed after hitting the end of the program with IF_pc.
    logic [2:0] dbg_termination_counter;
    
    logic [63:0] dbg_tick_counter; //counts once per clock cycle
    always_ff @ (posedge clk) begin
        dbg_tick_counter <= dbg_tick_counter + 1;
    end


    /* ================= PIPELINE LOGIC DOCUMENTATIION =========
     * WIP: (trying to codify and organize the logic of the pipeline stages) -janet
     *
     * - registers are IF, ID, EX, MEM, WB
     * - op currently being processed in EX_stage comes from EX_reg.XXXX, and so on
     * - a pipe reg can be !XX_reg.valid, in which case its contents are a "bubble"
     * - an op can be "trapping", i.e. it was excepted or interrupted
     * - a "trapping" op MUST still be valid, it's NOT A BUBBLE
     *
     *
     *  ==== High-level flow logic (i.e. what we want)
     *
     * - typically, an op in a stage moves forward each cycle
     * - if an op needs to be in stage XX for more than one cycle, it asserts XX_stall
     *
     *
     *  TODO: NOTE: this is not the current signals, this is "ideal signal organization"
     *
     *  --- Signals from inside a stage out to pipeline:
     *  - XX_stall (means this stage hasn't yet finished everything it needed to do to advance)
     *  - XX_is_trapped (means the op in this stage is excepted/interrupted, will affect behavior)
     *  - XX_stage.valid (if !valid, means this is empty space and can be overwritten)
     *
     *  --- Signals from pipeline into a stage:
     *  - XX_disable ( means that for whatever reason, this stage should do no work right now 
     *                 (e.g. disable memory access) )
     *  - XX_can_advance ( this op is able to advance freely (i.e. it can complete if necessary) )
     *  - XX_just_entered ( set on first cycle that op is in a stage )
     *
     *  --- Other traffic related signals (not clearly in or out)
     *  - XX_completing ( when XX_valid && !XX_stall && XX_can_advance, i.e. op is leaving the reg )
     *
     *
     *  --- ETC (not traffic control but might be useful)
     *  - XX_in_data_haz ( means this stage can't use the register values it uses )
     *
     *  ==== Low-level flow logic (i.e., how it's implemented)
     *  - each pipe_reg has inputs wr_en and gen_bubble
     *  - if !wr_en, the contents of the reg remain in place (don't advance)
     *  - if wr_en && gen_bubble, at clockedge the reg becomes a bubble (i.e. not valid, zeroed)
     *  - if (wr_en && !gen_bubble), at clkedge the reg takes in the contents of the previous reg
     *
     *  -NOTE: if (AA_stage.wr_en && !BB_stage.wr_en), the op in AA_stage will 
     *                                                 vanish (since it has nowhere to go)
     *  -NOTE: if (AA_stage.wr_en && BB_stage.gen_buble), the op in AA_stage will similarly vanish
     *                                                 (since BB_stage will ignore it's input anyway)
     */





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


    logic [1:0] curr_priv_mode;


    // ------------------------BEGIN IF STAGE--------------------------

    logic [63:0] IF_pc;
    logic [31:0] IF_inst;
    logic IF_fetch_valid; //if cache output is valid

    logic IF_disable; // IF should sit quiet if we're waiting for traps to drain
    assign IF_disable = trap_in_pipeline; //Make sure we disable both input and output

    logic IF_stall;
    assign IF_stall = !IF_fetch_valid; //note: fetch_valid might be a page fault

    // IF_is_executing is high only when the op in IF is passing into ID
    logic IF_is_executing;
    assign IF_is_executing = id_wr_en && !id_gen_bubble;


    logic        IF_gen_trap; //TODO: trap gen
    logic [63:0] IF_gen_trap_cause;
    logic [63:0] IF_gen_trap_val;

    // ==== send I$ requests into memory system
    logic [63:0] mem_sys_ic_req_addr; //cant assign directly to input of module, so do this instead
    logic mem_sys_ic_en;

    assign mem_sys_ic_req_addr = IF_pc;
    assign mem_sys_ic_en = !IF_disable; 

    // Get response from I$
    assign IF_fetch_valid = (mem_sys.ic_resp_valid);
    assign IF_inst =       (mem_sys.ic_resp_inst);

    // On page fault, send a trap instruction forward
    assign IF_gen_trap = mem_sys.ic_resp_page_fault;
    assign IF_gen_trap_cause = IF_gen_trap ? MCAUSE_PAGEFAULT_I : 0;
    assign IF_gen_trap_val   = IF_gen_trap ? IF_pc : 0; //on fault, mtval gets virtual address of op

    // ====  IF-stage next-PC logic
    always_ff @ (posedge clk) begin
        if (reset) begin
            $display("Entry: %x", entry);
            IF_pc <= entry;
        end 
        
        else if (if_wr_en) begin
            //TODO: IF_PC logic: (in order of priority)
            // if IF is disabled (i.e. there's a trap in the pipeline, we
            // don't care what happens

            // - These are the conditions, in order
            // - Conditions closer to the end of the pipeline take priority,
            //   since they typically flush out any preceding them
            // - Jumps and traps are special-cased, but still happen in
            //   priority order
            // - Can handle re-executing on a flush to any stage, even though
            //   we don't use most of them (just for completeness)

            if (priv_sys.is_xret) begin        // ===== Handle trap-related jumps
                IF_pc <= priv_sys.epc_addr & ~64'b011;
            end
            else if (priv_sys.jump_trap_handler) begin
                IF_pc <= priv_sys.handler_addr;
            end

            else if (flush_before_wb) begin     // === (this should never happen)
                $error("ERROR: FLUSH_BEFORE_WB should only happen if we're jumping for a trap");
            end

            else if (flush_before_mem) begin    // === Reexecute on a flush in mem
                if (!MEM_reg.valid) $error ("ERROR: flush_before_mem expects inst in MEM, found bubble");
                IF_pc <= MEM_reg.curr_pc + 4; // start after instruction in MEM
            end

            else if (EX_do_jump) begin          // === Do a jump
                    IF_pc <= jump_target_address;
            end


            else if (flush_before_ex) begin     // === Re-execute on a non-jump flush to EX (not typical)
                if(!EX_reg.valid) $error("ERROR: flush_before_ex expects inst in EX, found bubble");
                IF_pc <= EX_reg.curr_pc + 4;
            end
            else if (flush_before_id) begin     // === Re-execute on a non-jump flush to ID  (not typical)
                if(!ID_reg.valid) $error("ERROR: flush_before_id expects inst in ID, found bubble");
                IF_pc <= ID_reg.curr_pc + 4;
            end

            
            else begin                          // === Default PC logic: advance:  
                IF_pc <= IF_pc+4;
            end
        end
    end


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
        .curr_inst(),

        // === Trap signals
        .next_trapped   (IF_gen_trap),
        .next_trap_cause(IF_gen_trap ? IF_gen_trap_cause : 0),
        .next_trap_val  (IF_gen_trap ? IF_gen_trap_val   : 0),
        .curr_trapped(),
        .curr_trap_cause(),
        .curr_trap_val()
    );

    // ------------------------BEGIN ID STAGE--------------------------

    logic ID_stall;
    assign ID_stall = haz.data_hazard_ID;
    
    logic        ID_gen_trap; // Set in decoder
    logic [63:0] ID_gen_trap_cause;
    logic [63:0] ID_gen_trap_val;

    // Components decoded from IF_inst, set by decoder
    decoded_inst_t ID_deco; 

    Decoder d(
        .inst(ID_reg.curr_inst),
        .valid(ID_reg.valid),
        .pc(ID_reg.curr_pc),
        .out(ID_deco),

        .gen_trap(ID_gen_trap),
        .gen_trap_cause(ID_gen_trap_cause),
        .gen_trap_val(ID_gen_trap_val)
    );
    
    // Register file
    logic [63:0] ID_out1;
    logic [63:0] ID_out2;

    // Ecall values (FOR TEMP ECALL HACK)
    logic [63:0] a0, a1, a2, a3, a4, a5, a6, a7;

    // === Enable RegFile writeback USING SIGNALS FROM WB STAGE
    logic writeback_en; // enables writeback to regfile
	logic [63:0] WB_result;
	logic [4:0] WB_rd;
	logic WB_en_rd;
    assign writeback_en = WB_reg.valid && !WB_reg.curr_trapped && !wb_stage.stall && WB_en_rd; 
    // only wb on a valid instruction, not stalled (i.e. completed)
    // and which actually has something to writeback (en_rd)
    //TODO: change this to be WB_complete

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
        .curr_val_rs2(),

        // === Trap signals
        .next_trapped   (ID_gen_trap || ID_reg.curr_trapped),
        .next_trap_cause(ID_gen_trap ? ID_gen_trap_cause : ID_reg.curr_trap_cause), 
        .next_trap_val  (ID_gen_trap ? ID_gen_trap_val   : ID_reg.curr_trap_val), 
        .curr_trapped(),
        .curr_trap_cause(),
        .curr_trap_val()
    );

    // -----------------------BEGIN EX STAGE----------------------------

    decoded_inst_t EX_deco;
    assign EX_deco = EX_reg.curr_deco;

    logic        EX_gen_trap = 0; //TODO: trap gen
    logic [63:0] EX_gen_trap_cause = 0;
    logic [63:0] EX_gen_trap_val   = 0;

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
    logic EX_do_jump;

    // mask off bottommost bit of jump target: (according to RISCV spec)
    assign jump_target_address = (EX_deco.jump_absolute ? alu_out : (EX_reg.curr_pc + EX_deco.immed)) & ~64'b1;

    //Deciding whether to jump
    always_comb begin
        case (EX_deco.jump_if) inside
			JUMP_NO:		EX_do_jump = 0;
			JUMP_YES:		EX_do_jump = 1;
			JUMP_ALU_EQZ:	EX_do_jump = (alu_out == 0);
			JUMP_ALU_NEZ:	EX_do_jump = (alu_out != 0);
        endcase
		
    end


    logic [63:0] exec_result;

    logic ex_keep_pc_plus_immed = EX_deco.keep_pc_plus_immed;

    //Deciding EXEC_stage output
    always_comb begin
        if (EX_do_jump) begin // Jumps store return addr (pc+4)
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

        .next_do_jump(EX_do_jump),
        .next_jump_target(jump_target_address),
        .curr_do_jump(),
        .curr_jump_target(),


        // === Trap signals
        .next_trapped   (EX_gen_trap || EX_reg.curr_trapped),
        .next_trap_cause(EX_gen_trap ? EX_gen_trap_cause : EX_reg.curr_trap_cause), 
        .next_trap_val  (EX_gen_trap ? EX_gen_trap_val   : EX_reg.curr_trap_val), 
        .curr_trapped(),
        .curr_trap_cause(),
        .curr_trap_val()
    );

    // ------------------------BEGIN MEM STAGE--------------------------

    logic [63:0] mem_ex_rdata;   // Properly extended rdata
    logic [63:0] atomic_result;

    logic [63:0] csr_rs1_val;
    logic [63:0] csr_result;
    assign csr_rs1_val = (MEM_reg.curr_deco.csr_immed) ? MEM_reg.curr_deco.rs1 : MEM_reg.curr_data;

    logic [63:0] mem_stage_result;
    assign mem_stage_result = (MEM_reg.curr_deco.is_csr) ? csr_result :
                              (MEM_reg.curr_deco.is_atomic) ? atomic_result : mem_ex_rdata;

    //TODO: move priv_sys instantiation out of mem_stage section into
    //other-modules section
    Privilege_System priv_sys(
        .clk,
        .reset,

        // ==== MEM CSR op inputs (TODO: move these into mem_stage and rename)
        .valid(MEM_reg.valid),
        .addr(MEM_reg.curr_deco.immed),
        .val(csr_rs1_val),
        .is_csr(MEM_reg.curr_deco.is_csr),
        .csr_rw(MEM_reg.curr_deco.csr_rw),
        .csr_rs(MEM_reg.curr_deco.csr_rs),
        .csr_rc(MEM_reg.curr_deco.csr_rc),

        // output
        .csr_result(csr_result),
        
        // === TRAP inputs
        .trap_en           (WB_reg.valid && WB_reg.curr_trapped),
        .trap_cause        (WB_reg.curr_trap_cause),
        .trap_pc           (WB_reg.curr_pc),
        .trap_mtval        (WB_reg.curr_trap_val),
        .trap_is_ret       (WB_reg.curr_deco.is_trap_ret),
        .trap_ret_from_priv(WB_reg.curr_deco.trap_ret_priv),

        // outputs
        .handler_addr(),

        .is_xret(),
        .epc_addr(),

        // === Misc
        .modifying_satp(),
        .curr_priv_mode
    );

    MEM_Stage mem_stage(
        .clk,
        .reset,

        //inputs
        .inst(MEM_reg.curr_deco),
        .ex_data(MEM_reg.curr_data),
        .ex_data2(MEM_reg.curr_data2),
        .is_bubble(!MEM_reg.valid),
        .advance(mem_wr_en), //TODO: this might be incorrect if wb can stall

        .op_trapped(MEM_reg.curr_trapped), // was the incoming instruction trapped from prev stage

        //outputs
        .stall(),
        
        .gen_trap(), //did this stage generate a trap
        .gen_trap_cause(),
        .gen_trap_val(),
        
        .mem_ex_rdata(mem_ex_rdata),
        .atomic_result,

        .force_pipeline_flush(),

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
        .curr_pc(trap_pc),
        .curr_deco(),
        .curr_alu_result(),
        .curr_mem_result(),

        .next_do_jump(MEM_reg.curr_do_jump),
        .next_jump_target(MEM_reg.curr_jump_target),
        .curr_do_jump(),
        .curr_jump_target(),

        // === Trap signals
        .next_trapped   (mem_stage.gen_trap || MEM_reg.curr_trapped),
        .next_trap_cause(mem_stage.gen_trap ? mem_stage.gen_trap_cause : MEM_reg.curr_trap_cause), 
        .next_trap_val  (mem_stage.gen_trap ? mem_stage.gen_trap_val   : MEM_reg.curr_trap_val), 
        .curr_trapped(),
        .curr_trap_cause(),
        .curr_trap_val()
    );

    // ------------------------BEGIN WB STAGE---------------------------

	logic ecall_stall;

	wb_stage wb_stage(
		.clk(clk),
		.reset(reset),
		
        //TODO: TEMP: for ECALL hack
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

		.stall()
	);


    always_comb begin
        if (dbg_tick_counter % 1000 == 0 && WB_reg.valid && !ecall_stall && WB_reg.curr_do_jump) begin
            //$display("tick %x: jump to %x, from %x", dbg_tick_counter, WB_reg.curr_jump_target, WB_reg.curr_pc);
        end
    end

    // ------------------------END WB STAGE-----------------------------
    
    // -------Modules outside of pipeline (e.g. hazard detection)-------
    
    hazard_unit haz(
        .ID_deco(ID_deco),
        .EX_deco(EX_deco),
        .MEM_deco(MEM_reg.curr_deco),
        .WB_deco(WB_reg.curr_deco),

        .id_valid (ID_reg.valid),
        .ex_valid (EX_reg.valid),
        .mem_valid(MEM_reg.valid),
        .wb_valid (WB_reg.valid),

        // Outputs data hazards detected
        .data_hazard_ID()

    );



    // ============== FLUSHING LOGIC
    
    // doing jump
    // MEM force flush (for sfences or CSRs)
    logic MEM_force_flush = 0; //TODO: temp

    logic IF_is_trap;
    logic ID_is_trap;
    logic EX_is_trap;
    logic MEM_is_trap;
    logic WB_is_trap;
    assign IF_is_trap  = IF_gen_trap;
    assign ID_is_trap  = ID_gen_trap || ID_reg.curr_trapped;
    assign EX_is_trap  = EX_gen_trap || EX_reg.curr_trapped;
    assign MEM_is_trap = mem_stage.gen_trap || MEM_reg.curr_trapped;
    assign WB_is_trap  = WB_reg.curr_trapped;


    logic flush_before_id;
    logic flush_before_ex;
    logic flush_before_mem;
    logic flush_before_wb;
    
    logic trap_in_pipeline; // IF isn't a pipeline stage, so don't check there
    // Or else IF will disable itself in the same cycle that it detects a thing
    assign trap_in_pipeline = (ID_is_trap || EX_is_trap || MEM_is_trap || WB_is_trap);

    assign flush_before_id  = ID_is_trap  || 0;
    assign flush_before_ex  = EX_is_trap  || EX_do_jump;
    assign flush_before_mem = MEM_is_trap || mem_stage.force_pipeline_flush || priv_sys.modifying_satp;
    assign flush_before_wb  = WB_is_trap;  // THIS SHOULD NEVER FLUSH OUT AN OP FROM MEM

    always_ff @ (posedge clk) begin  // WARN US IF WE ACCIDENTALLY TRY TO FLUSH SOMETHING FROM MEM
        if (flush_before_wb && MEM_reg.valid)
            $error("ERROR: we should never flush an op out of MEM because of side effects");
        // MEM stage cant be flushed safely since it might have WIP ops
    end

    //assign flush_before_wb = WB_reg.curr_deco.is_ecall; //TODO OLD: ONLY FOR THE ECALL HACK

    

    traffic_control traffic(
        // Inputs (stalls from hazard unit)
        .if_stall(IF_stall),
        .id_stall(ID_stall),
        .ex_stall(0),  //EX is always single cycle
        .mem_stall(mem_stage.stall),
        .wb_stall(wb_stage.stall),

        // Whether that reg is actually holding anything at the moment
        .id_valid (ID_reg.valid),
        .ex_valid (EX_reg.valid),
        .mem_valid(MEM_reg.valid),
        .wb_valid (WB_reg.valid),

        //inputs
		.flush_before_id,
		.flush_before_ex,
        .flush_before_mem,
        .flush_before_wb,

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


    // ===== Icache and Dcache access is all routed into here
    MemorySystem #( ID_WIDTH, ADDR_WIDTH, DATA_WIDTH, STRB_WIDTH) mem_sys(
        .clk,
        .reset,

        .csr_SATP(priv_sys.satp_csr),
        .csr_SUM(0), //TODO: wirte this into priv_sys

        //I$ ports
        .ic_req_addr(mem_sys_ic_req_addr),  // this is assigned from a signal since it's an input
        .ic_en(1), // TODO: wire this to IF_disable
        .ic_resp_valid(),    //Outputs
        .ic_resp_page_fault(),
        .ic_resp_inst(),

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
            dbg_termination_counter <= 0;
        else if (IF_is_executing && IF_inst != 0) // Count resets for each real inst
            dbg_termination_counter <= 0;

        else if (IF_is_executing && IF_inst == 0) begin // Count advances for each null inst
            dbg_termination_counter <= dbg_termination_counter + 1;
/*
            if (dbg_termination_counter == 5) begin
                $display("===== Program terminated =====");
                $display("    IF_pc = 0x%0x", IF_pc);
                    for(int i = 0; i < 32; i++)
                    $display("    r%2.2d: %10d (0x%x)", i, rf.regs[i], rf.regs[i]);
                $finish;
            end
*/
        end
    end

    initial begin
            $display("Initializing top, entry point = 0x%x", entry);
    end
endmodule
