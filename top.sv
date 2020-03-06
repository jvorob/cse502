`include "Sysbus.defs"
`include "enums.sv"
`include "decoder.sv"
`include "alu.sv"
`include "regfile.sv"
`include "pipe_reg.sv"
`include "hazard.sv"
`include "icache.sv"
`include "dcache.sv"
`include "axi_interconnect.sv"

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
	// pipeline partially executed after hitting the end of the program with sm_pc.
    logic [2:0] counter;
    
    logic [63:0] sm_pc; //PC of axi-fetching state machine
    logic [31:0] ir;
    logic icache_valid;

    // Curr instruction and PC going to decoder
    logic [63:0] pc = sm_pc;
    logic [31:0] cur_inst = ir;

    logic enable_execute; //set by state machine, is high for one clock for each instr
    // until we have instruction cache, many clock cycles spent on AXI-fetch
    // need to disable continuously execute current instr while waiting 
    
    // Traffic controller signals:
    // gen_bubble
    logic gen_if_bubble;
    logic gen_id_bubble;
    logic gen_ex_bubble;
    logic gen_mem_bubble;
	logic gen_wb_bubble;

    // wr_en
    logic id_wr_en;
    logic ex_wr_en;
    logic mem_wr_en;
    logic wb_wr_en;

	// flush signals
    logic flush_before_wb;	// Used for ecall
	logic flush_before_ex;	// Used for jumps/branches

    // ------------------------BEGIN IF STAGE--------------------------
 
    wire [ID_WIDTH-1:0]     icache_m_axi_arid;
    wire [ADDR_WIDTH-1:0]   icache_m_axi_araddr;
    wire [7:0]              icache_m_axi_arlen;
    wire [2:0]              icache_m_axi_arsize;
    wire [1:0]              icache_m_axi_arburst;
    wire                    icache_m_axi_arlock;
    wire [3:0]              icache_m_axi_arcache;
    wire [2:0]              icache_m_axi_arprot;
    wire                    icache_m_axi_arvalid;
    wire                    icache_m_axi_arready;
    wire [ID_WIDTH-1:0]     icache_m_axi_rid;
    wire [DATA_WIDTH-1:0]   icache_m_axi_rdata;
    wire [1:0]              icache_m_axi_rresp;
    wire                    icache_m_axi_rlast;
    wire                    icache_m_axi_rvalid;
    wire                    icache_m_axi_rready;

    Icache icache (.*);

    // ------------------------END IF STAGE----------------------------

    ID_reg ID_reg(
        .clk,
        .reset,

        //traffic signals
        .wr_en(id_wr_en),
        .gen_bubble(!icache_valid || gen_if_bubble), // if no instruction, pipeline gets bubble (TODO TEMP)
        .bubble(),

        // incoming signals for next step's ID
        .next_pc(pc),
        .next_inst(cur_inst),

        // outgoing signals for current ID stage
        .curr_pc(),
        .curr_inst()
    );

    // ------------------------BEGIN ID STAGE--------------------------

    // Components decoded from cur_inst, set by decoder
    decoded_inst_t ID_deco; 

    Decoder d(
        .inst(ID_reg.curr_inst),

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
    assign writeback_en = WB_en_rd && !WB_reg.bubble && !gen_wb_bubble;  // dont write bubbles

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
        .gen_bubble(ID_reg.bubble || gen_id_bubble),
        .bubble(),

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
        .op(0), // This is unused I think?
        .is_load(EX_deco.is_load),
        .is_store(EX_deco.is_store),

        .result(alu_out)
    );

    // Jump logic
    logic [63:0] jump_target_address;
    logic do_jump;

    // mask off bottommost bit of jump target: (according to RISCV spec)
    assign jump_target_address = (EX_deco.jump_absolute ? alu_out : (EX_reg.curr_pc + EX_deco.immed)) & ~64'b1;

    //Deciding whether to jump
    always_comb begin
        case (EX_deco.jump_if) inside
			JUMP_NO:		do_jump = 0;
			JUMP_YES:		do_jump = 1;
			JUMP_ALU_EQZ:	do_jump = (alu_out == 0);
			JUMP_ALU_NEZ:	do_jump = (alu_out != 0);
        endcase
		
        if (counter != 1) begin
    		flush_before_ex = do_jump;
        end
        else begin
            flush_before_ex = 0;
        end
    end


    logic [63:0] exec_result;

    //Deciding EXEC_stage output
    always_comb begin
        if (do_jump) begin // Jumps store return addr (pc+4)
            exec_result = EX_reg.curr_pc + 4 ; //(For JAL/JALR. Branches will discard it anyway)

        end else if (EX_deco.keep_pc_plus_immed) begin //FOR AUIPC
            exec_result = EX_reg.curr_pc + EX_deco.immed;

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
        .gen_bubble(EX_reg.bubble || gen_ex_bubble),
        .bubble(),

        // Data coming in from EX
        .next_pc(EX_reg.curr_pc),
        .next_deco(EX_deco), // includes pc & immed
        .next_data(exec_result),  // result from ALU or other primary value
        .next_data2(EX_reg.curr_val_rs2), // extra value if needed (e.g. for stores, etc)

        // Data signals for current MEM step
        .curr_pc(),
        .curr_deco(),
        .curr_data(),
        .curr_data2()        
    );


    // ------------------------BEGIN MEM STAGE--------------------------

    // AXI signals
    wire [ID_WIDTH-1:0]     dcache_m_axi_awid;
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr;
    wire [7:0]              dcache_m_axi_awlen;
    wire [2:0]              dcache_m_axi_awsize;
    wire [1:0]              dcache_m_axi_awburst;
    wire                    dcache_m_axi_awlock;
    wire [3:0]              dcache_m_axi_awcache;
    wire [2:0]              dcache_m_axi_awprot;
    wire                    dcache_m_axi_awvalid;
    wire                    dcache_m_axi_awready;
    wire [DATA_WIDTH-1:0]   dcache_m_axi_wdata;
    wire [STRB_WIDTH-1:0]   dcache_m_axi_wstrb;
    wire                    dcache_m_axi_wlast;
    wire                    dcache_m_axi_wvalid;
    wire                    dcache_m_axi_wready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_bid;
    wire [1:0]              dcache_m_axi_bresp;
    wire                    dcache_m_axi_bvalid;
    wire                    dcache_m_axi_bready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_arid;
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_araddr;
    wire [7:0]              dcache_m_axi_arlen;
    wire [2:0]              dcache_m_axi_arsize;
    wire [1:0]              dcache_m_axi_arburst;
    wire                    dcache_m_axi_arlock;
    wire [3:0]              dcache_m_axi_arcache;
    wire [2:0]              dcache_m_axi_arprot;
    wire                    dcache_m_axi_arvalid;
    wire                    dcache_m_axi_arready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_rid;
    wire [DATA_WIDTH-1:0]   dcache_m_axi_rdata;
    wire [1:0]              dcache_m_axi_rresp;
    wire                    dcache_m_axi_rlast;
    wire                    dcache_m_axi_rvalid;
    wire                    dcache_m_axi_rready;

    logic [63:0] mem_ex_rdata;   // Properly extended rdata
    logic dcache_en;
    logic dcache_valid;
    logic write_done;

    mem_stage mem(
        .clk(clk),
        .reset(reset),
        .inst(MEM_reg.curr_deco),
        .ex_data(MEM_reg.curr_data),
        .ex_data2(MEM_reg.curr_data2),
        .is_bubble(MEM_reg.bubble),
        .dcache_valid(dcache_valid),
        .write_done(write_done),
        .dcache_en(dcache_en),
        .mem_ex_rdata(mem_ex_rdata),
        .*
    );

    // ------------------------END MEM STAGE----------------------------

    WB_reg WB_reg(
        .clk(clk),
        .reset(reset),

        //traffic signals
        .wr_en(wb_wr_en),
        .gen_bubble(MEM_reg.bubble || gen_mem_bubble),
        .bubble(),

        // Data signals coming in from MEM
        .next_pc(MEM_reg.curr_pc),
        .next_deco(MEM_reg.curr_deco),
        .next_alu_result(MEM_reg.curr_data),
        .next_mem_result(mem_ex_rdata),

        // Data signals for current WB step
        .curr_pc(),
        .curr_deco(),
        .curr_alu_result(),
        .curr_mem_result()
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
		
		.is_bubble(WB_reg.bubble),

		.alu_result(WB_reg.curr_alu_result),
		.mem_result(WB_reg.curr_mem_result),
		.inst(WB_reg.curr_deco),
		
		.result(WB_result),
		.rd(WB_rd),
		.en_rd(WB_en_rd),

		.ecall_stall(ecall_stall)
	);

    // ------------------------END WB STAGE-----------------------------
    
    // -------Modules outside of pipeline (e.g. hazard detection)-------
    
    logic haz_id_stall;
    logic haz_ex_stall;
    logic haz_mem_stall;
    logic haz_wb_stall;
    
    hazard_unit haz(
        .ID_deco(ID_deco),
        .id_bubble(ID_reg.bubble),

        .EX_deco(EX_deco),
        .ex_bubble(EX_reg.bubble),

        .MEM_deco(MEM_reg.curr_deco),
        .mem_bubble(MEM_reg.bubble),
		
		.dcache_valid(dcache_valid),
		.write_done(write_done),
		.dcache_enable(dcache_en),

        .WB_deco(WB_reg.curr_deco),
        .wb_bubble(WB_reg.bubble),

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
        .id_stall(haz_id_stall),
        .ex_stall(haz_ex_stall),
        .mem_stall(haz_mem_stall),
        .wb_stall(haz_wb_stall),

        .flush_before_wb(flush_before_wb),
		.flush_before_ex(flush_before_ex),

        // Output gen bubbles
        .if_bubble(gen_if_bubble),
        .id_bubble(gen_id_bubble),
        .ex_bubble(gen_ex_bubble),
        .mem_bubble(gen_mem_bubble),
		.wb_bubble(gen_wb_bubble),

        // Output wr_en
        .id_wr_en(id_wr_en),
        .ex_wr_en(ex_wr_en),
        .mem_wr_en(mem_wr_en),
        .wb_wr_en(wb_wr_en)
    );


    assign enable_execute = icache_valid;

    AXI_interconnect axi_interconnect (.*);

    always_ff @ (posedge clk) begin
        if (sm_pc[1:0] != 2'b00) 
            $error("ERROR: executing unaligned instruction at PC=%x", sm_pc);
    end

	// This is used to let the instructions in the middle of the pipeline finish
	// executing before we stop. This is because there might still be instructions in the
	// pipeline partially executed after hitting the end of the program with sm_pc.
    // logic [2:0] counter;

    always_ff @ (posedge clk) begin
        if (reset) begin
            $display("Entry: %x", entry);
            sm_pc <= entry;
            counter <= 0;
        end
        else if (icache_valid) begin
            if (flush_before_wb) begin
                counter <= 0;
				// Must refetch flushed instructions.
				// Currently, only ecall will make use of this.
				sm_pc <= WB_reg.curr_pc + 4;
            end
			else if (flush_before_ex) begin
				counter <= 0;
				// Must refetch flushed instructions.
				// Currently, only branches/jumps will make use of this.
				if (do_jump) begin
					sm_pc <= jump_target_address;
				end
				else begin
					sm_pc <= EX_reg.curr_pc + 4; // TODO: uh this is wrong, we should only flush if we did the jump
				end
			end
            else if (ir == 0 && counter < 5) begin // === Run until we hit a 0x0000_0000 instruction (wait a few more cycles for pipeline to finish)
                counter <= counter + 1;
            end
            else if (counter == 5) begin
                $display("===== Program terminated =====");
                $display("    PC = 0x%0x", pc);
                    for(int i = 0; i < 32; i++)
                    $display("    r%2.2d: %10d (0x%x)", i, rf.regs[i], rf.regs[i]);
                $finish;
            end
            else begin
				counter <= 0;
                if (!id_wr_en) begin
                    sm_pc <= sm_pc;
                end
                else begin
                    sm_pc <= sm_pc + 64'h4;
                end
            end
        end
    end

  initial begin
        $display("Initializing top, entry point = 0x%x", entry);
  end
    
endmodule
