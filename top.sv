`include "Sysbus.defs"
`include "enums.sv"
`include "decoder.sv"
`include "alu.sv"
`include "regfile.sv"
`include "pipe_reg.sv"
`include "hazard.sv"
`include "icache.sv"

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
  output  reg  [ID_WIDTH-1:0]    m_axi_arid,
  output  reg  [ADDR_WIDTH-1:0]  m_axi_araddr,
  output  reg  [7:0]             m_axi_arlen,
  output  reg  [2:0]             m_axi_arsize,
  output  reg  [1:0]             m_axi_arburst,
  output  reg                    m_axi_arlock,
  output  reg  [3:0]             m_axi_arcache,
  output  reg  [2:0]             m_axi_arprot,
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
    logic gen_id_bubble;
    logic gen_ex_bubble;
    logic gen_mem_bubble;
    logic gen_wb_bubble;

    // wr_en
    logic id_wr_en;
    logic ex_wr_en;
    logic mem_wr_en;
    logic wb_wr_en;

    // ------------------------BEGIN IF STAGE--------------------------

    Icache icache (.*);

    // ------------------------END IF STAGE----------------------------

    ID_reg ID_reg(
        .clk,
        .reset,

        //traffic signals
        .wr_en(id_wr_en),
        .gen_bubble(!icache_valid), // if no instruction, pipeline gets bubble (TODO TEMP)
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

    // === Enable RegFile writeback USING SIGNALS FROM WB STAGE
    logic writeback_en; // enables writeback to regfile
    assign writeback_en = WB_reg.curr_deco.en_rd && !WB_reg.bubble;  // dont write bubbles

    RegFile rf(
        .clk(clk),
        .reset(reset),

        .read_addr1(ID_deco.rs1),
        .read_addr2(ID_deco.rs2),

        .wb_addr(WB_reg.curr_deco.rd),
        .wb_data(WB_result),
        .wb_en(writeback_en),

        .out1(ID_out1),
        .out2(ID_out2)
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

        .result(alu_out)
    );

    // Jump logic
    logic [63:0] jump_target_address;
    logic do_jump;

    // mask off bottommost bit of jump target: (according to RISCV spec)
    assign jump_target_address = (EX_deco.jump_absolute ? alu_out : (EX_reg.curr_pc + EX_deco.immed)) & ~64'b1;

    always_comb begin
        case (EX_deco.jump_if) inside
            JUMP_NO:      do_jump = 0;
            JUMP_YES:     do_jump = 1;
            JUMP_ALU_EQZ: do_jump = (alu_out == 0);
            JUMP_ALU_NEZ: do_jump = (alu_out != 0);
        endcase
    end


    logic [63:0] exec_result;
    assign exec_result = EX_deco.keep_pc_plus_immed ? EX_reg.curr_pc + EX_deco.immed : alu_out;


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
        .next_data2(0 /*TODO*/), // extra value if needed (e.g. for stores, etc)

        // Data signals for current MEM step
        .curr_pc(),
        .curr_deco(),
        .curr_data(),
        .curr_data2()        
    );


    // ------------------------BEGIN MEM STAGE--------------------------

    //TODO: noop for now, otherwise compute some result for mem stuff

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
        .next_mem_result(0 /*TODO*/),

        // Data signals for current WB step
        .curr_pc(),
        .curr_deco(),
        .curr_alu_result(),
        .curr_mem_result()
    );

    // ------------------------BEGIN WB STAGE---------------------------
    
    logic [63:0] WB_result;
    assign WB_result = WB_reg.curr_alu_result;

    logic [4:0] WB_rd = WB_reg.curr_deco.rd;
    logic WB_en_rd = WB_reg.curr_deco.en_rd;
    //TODO: set proper regfile writeback: switch btwn ALU and mem

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

        .WB_deco(WB_reg.curr_deco),
        .wb_bubble(WB_reg.bubble),

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

        // Output gen bubbles
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

    always_ff @ (posedge clk) begin
        if (sm_pc[1:0] != 2'b00) 
            $error("ERROR: executing unaligned instruction at PC=%x", sm_pc);
    end

    always_ff @ (posedge clk) begin
        if (reset)
            sm_pc <= entry;
        else if (icache_valid) begin
            if (ir == 0) begin // === Run until we hit a 0x0000_0000 instruction
                $display("===== Program terminated =====");
                $display("    PC = 0x%0x", pc);
                    for(int i = 0; i < 32; i++)
                    $display("    r%2.2d: %10d (0x%x)", i, rf.regs[i], rf.regs[i]);
            

                $finish;
            end
            else begin
                if (do_jump) begin
                    sm_pc <= jump_target_address;
                end 
                else if (!id_wr_en) begin
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
