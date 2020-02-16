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
    // need to disa continuously execute current instr while waiting 


    // ------------------------BEGIN IF STAGE--------------------------

    Icache icache (.*);

    // ------------------------END IF STAGE----------------------------

    if_id_reg if_id(
        .clk(clk),
        .reset(reset),
        .stall(),
        .in_inst(),
        .out_inst()
    );

    // ------------------------BEGIN ID STAGE--------------------------

    // Components decoded from cur_inst, set by decoder
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic en_rs1;
    logic en_rs2;
    logic en_rd;
    logic [63:0] imm;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] op;

    // Special signals
    logic keep_pc_plus_immed; //(for AUIPC, we already have a separate PC+(...) adder
    // need to mux that into exec-stage output

    logic alu_use_immed;// (ALU input B should be immed, not rs2)
    logic alu_width_32; // (-W Op)

    Decoder d(
        .inst(cur_inst),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .en_rs1(en_rs1),
        .en_rs2(en_rs2),
        .en_rd(en_rd),
        .imm(imm),
        .funct3(funct3),
        .funct7(funct7),
        .op(op),

        .alu_use_immed,
        .keep_pc_plus_immed
    );
    
    // Register file
    logic [63:0] out1;
    logic [63:0] out2;
    logic writeback_en; // enables writeback to regfile
    assign writeback_en = en_rd && enable_execute; // if curr op had a dest reg

    RegFile rf(
        .clk(clk),
        .reset(reset),
        .read_addr1(rs1),
        .read_addr2(rs2),
        .wb_addr(rd),
        .wb_data(exec_result),
        .wb_en(writeback_en),
        .out1(out1),
        .out2(out2)
    );
    
    // -----------------------END ID STAGE------------------------------

    id_ex_reg id_ex(
        .clk(clk),
        .reset(reset),
        .stall(),
        .funct3()
    );

    // -----------------------BEGIN EX STAGE----------------------------

    // == ALU signals
    logic [63:0] alu_out;
    logic [63:0] alu_b_input;
    assign alu_b_input = alu_use_immed ? imm : out2;

    Alu a(
        .a(out1),
        .b(alu_b_input),
        .funct3(funct3),
        .funct7(funct7),
        .op(op),

        .width_32(alu_width_32),

        .result(alu_out)
    );

    // ------------------------END EX STAGE-----------------------------

    ex_mem_reg ex_mem(
        .clk(clk),
        .reset(reset),
        .stall(),
        .in_alu_result(),
        .out_alu_result()
    );

    // ------------------------BEGIN MEM STAGE--------------------------

    // ------------------------END MEM STAGE----------------------------

    mem_wb_reg mem_wb(
        .clk(clk),
        .reset(reset),
        .stall(),
        .in_mem_result(),
        .in_rd(),
        .in_en_rd(),
        .out_mem_result(),
        .out_rd(),
        .out_en_rd()
    );

    // ------------------------BEGIN WB STAGE---------------------------
    logic [63:0] exec_result;

    //TODO: this won't be correct because this isn't the instruction's PC, it's the state machine's
    assign exec_result = keep_pc_plus_immed ? pc + imm : alu_out;

    // ------------------------END WB STAGE-----------------------------
    

    // -------Modules outside of pipeline (e.g. hazard detection)-------
    hazard_unit haz(
        .clk(clk),
        .hazard()
    );


    assign enable_execute = icache_valid;

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
            else
                sm_pc <= sm_pc + 64'h4;
        end
    end

  initial begin
        $display("Initializing top, entry point = 0x%x", entry);
  end
    
endmodule
