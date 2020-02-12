`include "Sysbus.defs"
`include "enums.sv"
`include "decoder.sv"
`include "alu.sv"
`include "regfile.sv"
`include "pipe_reg.sv"
`include "hazard.sv"

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
  output  reg                    m_axi_arvalid,
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

    logic [2:0] state;
    logic [63:0] sm_pc; //PC of axi-fetching state machine
    logic [63:0] ir;

    // Curr instruction and PC going to decoder
    logic [63:0] pc;
    logic [31:0] cur_inst;

    logic enable_execute; //set by state machine, is high for one clock for each instr
    // until we have instruction cache, many clock cycles spent on AXI-fetch
    // need to disa continuously execute current instr while waiting 


    // ------------------------BEGIN IF STAGE--------------------------




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




    // === Run until we hit a 0x0000_0000 instruction
    always_ff @ (posedge clk) begin
        if (cur_inst == 0 && !reset) begin 
            $display("===== Program terminated =====");
            $display("    PC = 0x%0x", pc);
            for(int i = 0; i < 32; i++)
                $display("    r%2.2d: %10d (0x%x)", i, rf.regs[i], rf.regs[i]);
            

            $finish;
        end
    end

    // === Main state machine

    always_ff @ (posedge clk) begin
        if (reset) begin
            cur_inst <= -1; // we exit when this is 0000, so start at FFFF

            state <= 3'h0;
            sm_pc <= entry;

            enable_execute <= 0;

            m_axi_arid <= 0;      // master id
            m_axi_arlen <= 8'h7;  // +1, =8 words requested
            m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            m_axi_arlock <= 1'b0; // no lock
            m_axi_arcache <= 4'h0;// no cache
            m_axi_arprot <= 3'h6; // enum, means something
            m_axi_arvalid <= 1'b0;// signal
            m_axi_rready <= 1'b0; // signal
        end else begin
            case(state)
            3'h0: begin  // Start Read

                if(!m_axi_arready || !m_axi_arvalid) begin
                    // It's addressed by bytes, even though you don't get full granularity at byte level
                    m_axi_araddr <= sm_pc[63:0];
                    m_axi_arvalid <= 1'b1;
                end else begin
                    sm_pc <= sm_pc + 64'h8;
                    m_axi_rready <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    state <= 3'h1;
                end

                enable_execute <= 0;
            end
            3'h1: begin // Address Accepted / Awaiting Read Valid
                if(m_axi_rvalid) begin
                    ir <= m_axi_rdata;
                    state <= 3'h2;
                end
            end
            3'h2: begin // Wait for remaining blocks to be sent
                if(m_axi_rlast) begin
                    m_axi_rready <= 1'b0;
                    state <= 3'h3;
                end
            end
            3'h3: begin // Read done, decode low
                cur_inst <= ir[31:0];
                pc <= sm_pc - 8;
                state <= 3'h4;
                enable_execute <= 1; //UGH this is really gross, 
                // we should move to the state-machine style where all effects
                // are combinational, based on the current state, not latched
                // at state transitions. TODO --Jan
            end
            3'h4: begin // Decode hi
                cur_inst <= ir[63:32];
                pc <= sm_pc - 4;
                state <= 3'h0;
                enable_execute <= 1;
            end
            default: state <= 3'h0;
            endcase
        end
    end
    

  initial begin
        $display("Initializing top, entry point = 0x%x", entry);
  end
    
endmodule
