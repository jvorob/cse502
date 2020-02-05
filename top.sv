`include "Sysbus.defs"


module Decoder
(
    input [31:0] inst,
    output [4:0] rs1,
    output [4:0] rs2,
    output [4:0] rd,
    output en_rs1,
    output en_rs2,
    output en_rd,
    output [63:0] imm,
    output [2:0] func3,
    output [6:0] func7,
    output [6:0] op
);


endmodule

module RegFile
(
    input clk,
    input [4:0] read_addr1,
    input [4:0] read_addr2,
    input [4:0] wb_addr,
    input [63:0] wb_data,
    input wb_en,
    output [63:0] out1,
    output [63:0] out2
);

endmodule

module Alu
(
    input [63:0] a,         // rs1
    input [63:0] b,         // rs2 or immediate
    input [2:0] func3,
    input [6:0] func7,
    input [6:0] op,
    output [63:0] result
);


endmodule


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

    logic [63:0] pc;
    logic [2:0] state;
    logic [63:0] ir;

    typedef enum bit[6:0] {
        OP_LOAD       = 7'b0000011 ,
        OP_LOAD_FP    = 7'b0000111 , // not used
        OP_CUSTOM0    = 7'b0001011 , // not used
        OP_MISC_MEM   = 7'b0001111 ,
        OP_OP_IMM     = 7'b0010011 ,
        OP_AUIPC      = 7'b0010111 ,
        OP_IMM_32     = 7'b0011011 ,
        OP_RSRVD1     = 7'b0011111 , // not used
        
        OP_STORE      = 7'b0100011 ,
        OP_STORE_FP   = 7'b0100111 , // not used
        OP_CUSTOM1    = 7'b0101011 , // not used
        OP_AMO        = 7'b0101111 , // not used
        OP_OP         = 7'b0110011 ,
        OP_LUI        = 7'b0110111 ,
        OP_OP_32      = 7'b0111011 ,
        OP_RSRVD2     = 7'b0111111 , // not used
        
        OP_MADD       = 7'b1000011 , // not used
        OP_MSUB       = 7'b1000111 , // not used
        OP_NMSUB      = 7'b1001011 , // not used
        OP_NMADD      = 7'b1001111 , // not used
        OP_OP_FP      = 7'b1010011 , // not used
        OP_RSRVD3     = 7'b1010111 , // not used
        OP_CUSTOM2    = 7'b1011011 , // not used
        OP_RSRVD4     = 7'b1011111 , // not used
        
        OP_BRANCH     = 7'b1100011 ,
        OP_JALR       = 7'b1100111 ,
        OP_RSRVD5     = 7'b1101011 ,
        OP_JAL        = 7'b1101111 ,
        OP_SYSTEM     = 7'b1110011 ,
        OP_RSRVD6     = 7'b1110111 , // not used
        OP_CUSTOM3    = 7'b1111011 , // not used
        OP_RSRVD7     = 7'b1111111   // not used
    } Opcode;
    
    
    // Values of F3 for Integer Register-Register Operations
    typedef enum bit[2:0] {
        F3OP_ADD_SUB  = 3'b000,
        F3OP_SLL      = 3'b001,
        F3OP_SLT      = 3'b010,
        F3OP_SLTU     = 3'b011,
        F3OP_XOR      = 3'b100,
        F3OP_SRX      = 3'b101, // SRL/SRA
        F3OP_OR       = 3'b110,
        F3OP_AND      = 3'b111
    } Funct3_Op;
    
    // Values of F3 for immediate ops
    typedef enum bit[2:0] {
        F3OPI_ADDI  = 3'b000,
        F3OPI_SLLI  = 3'b001,
        F3OPI_SLTI  = 3'b010,
        F3OPI_SLTIU = 3'b011,
        F3OPI_XORI  = 3'b100,
        F3OPI_SRXI  = 3'b101, // SRL/SRA
        F30PI_ORI   = 3'b110,
        F3OPI_ANDI  = 3'b111
    } Funct3_iOp;
    
    // Values of F3 for branches
    typedef enum bit[2:0] {
        F3B_BEQ  = 3'b000,
        F3B_BNE  = 3'b001,
        F3B_BLT  = 3'b100,
        F3B_BGE  = 3'b101,
        F3B_BLTU = 3'b110,
        F3B_BGEU = 3'b111
    } Funct3_Branch;
    
    // Values of F3 for RV32M
    typedef enum bit[2:0] {
        F3M_MUL    = 3'b000,
        F3M_MULH   = 3'b001,
        F3M_MULHSU = 3'b010,
        F3M_MULHU  = 3'b011,
        F3M_DIV    = 3'b100,
        F3M_DIVU   = 3'b101,
        F3M_REM    = 3'b110,
        F3M_REMU   = 3'b111
    } Funct3_RV32M;
    
    // Values of F3 for RV64M
    typedef enum bit[2:0] {
        F3M_MULW   = 3'b000,
        F3M_DIVW   = 3'b100,
        F3M_DIVUW  = 3'b101,
        F3M_REMW   = 3'b110,
        F3M_REMUW  = 3'b111
    } Funct3_RV64M;
    
    // Values of F3 for various 64-bit ops
    typedef enum bit[2:0] {
        F3OP_ADDW_SUBW = 3'b000,
        F3OP_SLLW      = 3'b001,
        F3OP_SRXW      = 3'b101
    } Funct3_Op64;
      
    // Values of F3 for RV64I immediate ops
    typedef enum bit[2:0] {
        F3I64_ADDIW  = 3'b000,
        F3I64_SLLIW  = 3'b001,
        F3I64_SRXIW  = 3'b101
    } Funct3_RV64Iimm;

    // Values of F3 for fence instructions
    typedef enum bit[2:0] {
        F3_FENCE    = 3'b000,
        F3_FENCE_I  = 3'b001
    } Funct3_Fence;
    
    // Values of F3 for system instructions
    typedef enum bit[2:0] {
        F3_ECALL_EBREAK = 3'b000,
        F3_CSRRW        = 3'b001,
        F3_CSRRS        = 3'b010,
        F3_CSRRC        = 3'b011,
        F3_CSRRWI       = 3'b101,
        F3_CSRRSI       = 3'b110,
        F3_CSRRCI       = 3'b111
    } Funct3_System;
    
    // Values of F3 for load instructions
    typedef enum bit[2:0] {
        F3_LD       = 3'b011,
        F3_LWU      = 3'b110
    } Funct3_Load;

    // Values of F3 for store instructions
    typedef enum bit[2:0] {
        F3_SD       = 3'b011
    } Funct3_Store;

    logic [31:0] cur_inst;

    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic en_rs1;
    logic en_rs2;
    logic en_rd;
    logic [63:0] imm;
    logic [2:0] func3;
    logic [6:0] func7;
    logic [6:0] op;

    Decoder d(
        .inst(cur_inst),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .en_rs1(en_rs1),
        .en_rs2(en_rs2),
        .en_rd(en_rd),
        .imm(imm),
        .func3(func3),
        .func7(func7),
        .op(op)
    );

    logic [63:0] out1;
    logic [63:0] out2;

    RegFile rf(
        .clk(clk),
        .read_addr1(rs1),
        .read_addr2(rs2),
        .wb_addr(rd),
        .wb_data(alu_out),
        .wb_en(en_rd),              // still needs to be modified
        .out1(out1),
        .out2(out2)
    );
    
    logic [63:0] alu_out;

    Alu a(
        .a(out1),
        .b(out2),
        .func3(func3),
        .func7(func7),
        .op(op),
        .result(alu_out)
    );


    function void decode(input logic[31:0] inst);

    Opcode op = inst[6:0];

    // There's 5 different kinds of immediates: I, S, SB, U, UJ
    // NOTE: When immediates need to be sign-extended,
    //       you can always take sign from inst[31]
    logic [11:0]  immed_I  = inst[31:20];
    logic [11:0]  immed_S  = { inst[31:                   25], inst[11:        7] };
    logic [12:0]  immed_SB = { inst[31], inst[7], inst[30:25], inst[11:8],   1'b0 };
    logic [31:0]  immed_U  = { inst[31:          12],                       12'b0 };
    logic [20:0]  immed_UJ = { inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 } ;

    logic [4:0] rs1 = inst[19:15];
    logic [4:0] rs2 = inst[24:20];
    logic [4:0] rd  = inst[11: 7];
    logic [2:0] funct3 = inst[14:12];
    logic [6:0] funct7 = inst[31:25];
    logic [5:0] shamt = inst[25:20];
    logic [11:0] csr = inst[31:20];
    logic [4:0] zimm = inst[19:15];
    logic [3:0] pred = inst[27:24];
    logic [3:0] succ = inst[23:20];


    $display("\n");
    $display("Decoding instruction %b ", inst);
    $display("got opcode %s ('%b\')", op.name(), op);

    case (op) inside
      OP_LUI: begin
        $display("lui, r%0d, 0x%x", rd, immed_U);
      end
      OP_AUIPC: begin
        $display("auipc r%d, 0x%x", rd, immed_U);
      end
      OP_JAL: begin
        $display("jal 0x%x, return addr in r%0d'", immed_UJ, rd);
      end
      OP_JALR: begin
        if (funct3 != 3'b000) $error("ERROR: Invalid funct3 for JALR op, '%b'", funct3);
        $display("jalr 0x%x(r%0d), return addr in r%0d'", immed_I, rs1, rd);
      end

      OP_BRANCH: begin
        case (funct3) inside
          F3B_BEQ, F3B_BNE, F3B_BLT, F3B_BGE, F3B_BLTU, F3B_BGEU: begin
            Funct3_Branch branch_code = funct3;
            $display("Branch op: %s r%0d, r%0d, to 0x%x", branch_code.name, rs1, rs2, immed_SB);
          end
          default: begin
            $error("ERROR: Invalid funct3 for BRANCH op, '%b'", funct3);
          end
        endcase
      end

      OP_LOAD: begin
        //TODO --Jan
        case (funct3) inside
            F3_LWU:  $display("lwu r%0d, %0d(r%0d)", rd, immed_I, rs1);
            F3_LD:   $display("ld r%0d, %0d(r%0d)", rd, immed_I, rs1);
            default: $display("Invalid instruction for opcode=OP_LOAD.");
        endcase
      end
      OP_STORE: begin
        //TODO --Jan
        case (funct3) inside
            F3_SD: $display("sd r%0d, %0d(r%0d)", rs2, immed_S, rs1);
            default: $display("Invalid instruction for opcode=OP_STORE.");
        endcase
      end

      OP_OP_IMM: begin
        Funct3_iOp iOp_code = funct3;
        case (iOp_code) inside
          F3OPI_SLLI: begin
            if (funct7[6:1] != 6'b00_0000) $error("ERROR: Invalid funct7 for SLLI op, '%b'", funct7[6:1]);
            $display("SLLI r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
          end
          F3OPI_SRXI: begin
            if (funct7[6:1] == 6'b00_0000) $display("SRLI r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
            else if (funct7[6:1] == 6'b01_0000) $display("SRAI r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
            else $error("ERROR: Invalid funct7 for SRLI / SRAI op, '%b'", funct7[6:1]);
          end

          F3OP_ADD_SUB: $display("addi  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
          F3OP_SLT:     $display("slti  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
          F3OP_SLTU:    $display("sltiu r%0d, r%0d, 0x%x", rd, rs1, immed_I);
          F3OP_XOR:     $display("xori  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
          F3OP_OR:      $display("ori   r%0d, r%0d, 0x%x", rd, rs1, immed_I); 
          F3OP_AND:     $display("andi  r%0d, r%0d, 0x%x", rd, rs1, immed_I);

        endcase
      end

      OP_OP: begin
        // Multiply-ops have funct7 = 000_0001
        if (funct7[0]) begin
          Funct3_RV32M RV32M_code = funct3;
          if (funct7 != 7'b000_0001) $error("ERROR: Invalid funct7 for RV32M op, '%b'", funct7);

          $display("RV32M op: %s r%0d, r%0d, r%0d", RV32M_code.name(), rd, rs1, rs2);
        end

        // Normal ops have funct7 = 0?0_0000, funct7[5] set for sub, SRA
        else if (funct7 == 7'b000_0000) begin
            case (funct3) inside
                F3OP_ADD_SUB: $display("add r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_SLL:     $display("sll r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_SLT:     $display("slt r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_SLTU:    $display("sltu r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_XOR:     $display("xor r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_SRX:     $display("srl r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_OR:      $display("or r%0d, r%0d, r%0d", rd, rs1, rs2); 
                F3OP_AND:     $display("and r%0d, r%0d, r%0d", rd, rs1, rs2);
                default:      $display("Invalid instruction for opcode=OP_OP and funct7=7'b000_0000.");
            endcase
        end
        else if (funct7 == 7'b010_0000) begin
            case (funct3) inside
                F3OP_ADD_SUB: $display("sub r%0d, r%0d, r%0d", rd, rs1, rs2);
                F3OP_SRX: $display("sra r%0d, r%0d, r%0d", rd, rs1, rs2);
                default: $display("Invalid instruction for opcode=OP_OP and funct7=7'b010_0000.");
            endcase 
        end
        else begin
            $display("Invalid instruction for opcode=OP_OP.");
        end
      end

      OP_IMM_32: begin
        Funct3_RV64Iimm RV64Iimm_code = funct3;
        case (RV64Iimm_code) inside
          F3I64_ADDIW: $display("ADDIW r%0d, r%0d, 0x%x", rd, rs1, immed_I);
          F3I64_SLLIW: begin
            if (funct7 != 7'b000_0000) $error("ERROR: Invalid funct7 for SLLIW op, '%b'", funct7);
            $display("SLLIW r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
          end
          F3I64_SRXIW: begin
            if (funct7 == 7'b000_0000) $display("SRLIW r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
            else if (funct7 == 7'b010_0000) $display("SRAIW r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
            else $error("ERROR: Invalid funct7 for SRLIW / SRAIW op, '%b'", funct7);
          end
          default: $error("ERROR: Invalid funct3 for 64-bit immediate op, '%b'", funct3);
          // -- TODO: there's a bunch more of these?
        endcase
      end 

      OP_OP_32: begin
        // Multiply ops
        if (funct7[0]) begin
          if (funct7 != 7'b000_0001) $error("ERROR: Invalid funct7 for RV64M op, '%b'", funct7);
          case (funct3) inside
            F3M_MULW, F3M_DIVW, F3M_DIVUW, F3M_REMW, F3M_REMUW: begin
              Funct3_RV64M RV64M_code = funct3;
              $display("RV64M op: %s r%0d, r%0d, r%0d", RV64M_code.name(), rd, rs1, rs2);
            end
            default: $error("ERROR: Invalid funct3 for RV64M op, '%b'", funct3);
          endcase

        // Normal ops
        end else begin
        Funct3_Op64 Op64_code = funct3;
        case (Op64_code) inside
            F3OP_ADDW_SUBW: begin
            if (funct7 == 7'b000_0000) $display("ADDW r%0d, r%0d, r%0d", rd, rs1, rs2);
            else if (funct7 == 7'b010_0000) $display("SUBW r%0d, r%0d, r%0d", rd, rs1, rs2);
            else $error("ERROR: Invalid funct7 for ADDW / SUBW op, '%b'", funct7);
            end
            F3OP_SLLW: begin
            if (funct7 != 7'b000_0000) $error("ERROR: Invalid funct7 for SLLW op, '%b'", funct7);
            $display("SLLW r%0d, r%0d, r%0d", rd, rs1, rs2);
            end
            F3OP_SRXW: begin
            if (funct7 == 7'b000_0000) $display("SRLW r%0d, r%0d, r%0d", rd, rs1, rs2);
            else if (funct7 == 7'b010_0000) $display("SRAW r%0d, r%0d, r%0d", rd, rs1, rs2);
            else $error("ERROR: Invalid funct7 for SRLW / SRAW op, '%b'", funct7);
            end
            // -- TODO: there's a bunch more of these?
        endcase
        end
      end


      OP_MISC_MEM: begin
        if (rd == 0 && funct3 == F3_FENCE && rs1 == 0 && immed_I[11:8] == 0) begin
            $display("fence pred=%0d, pred=%0d", immed_I[7:4], immed_I[3:0]);
        end
        else if (rd == 0 && funct3 == F3_FENCE_I && rs1 == 0 && immed_I == 0) begin
            $display("fence.i");
        end else begin
            $display("Invalid instruction for opcode=OP_MISC_MEM.");
        end
      end

      OP_SYSTEM: begin
        case (funct3) inside
            F3_ECALL_EBREAK: begin
                if (immed_I[0] == 0)
                    $display("ecall");
                else if (immed_I[0] == 1)
                    $display("ebreak");
                else
                    $display("Invalid instruction for opcode=OP_SYSTEM and funct3=F3_ECALL_EBREAK.");
            end
            F3_CSRRW: begin
                $display("csrrw rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
            end
            F3_CSRRS: begin
                $display("csrrs rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
            end
            F3_CSRRC: begin
                $display("csrrc rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
            end
            F3_CSRRWI: begin
                $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
            end
            F3_CSRRSI: begin
                $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
            end
            F3_CSRRCI: begin
                $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
            end
            default: $display("Invalid instruction for opcode=OP_SYSTEM.");
        endcase
      end


      default: begin
        $display("Not recognized instruction.");
        $display("got opcode %s ('%b\')", op.name(), op);

        $display(" I-Immed is %x (%b)", immed_I, immed_I);
        $display(" S-Immed is %x (%b)", immed_S, immed_S);
        $display("SB-Immed is %x (%b)", immed_SB, immed_SB);
        $display(" U-Immed is %x (%b)", immed_U, immed_U);
        $display("UJ-Immed is %x (%b)", immed_UJ, immed_UJ);
      end
    endcase


    endfunction


  always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 3'h0;
            pc <= entry;
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
                    m_axi_araddr <= pc[63:0];
                    m_axi_arvalid <= 1'b1;
                end else begin
                    pc <= pc + 64'h8;
                    m_axi_rready <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    state <= 3'h1;
                end
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
                decode(ir[31:0]);
                state <= 3'h4;
            end
            3'h4: begin // Decode hi
                decode(ir[63:32]);
                state <= 3'h0;
            end
            default: state <= 3'h0;
            endcase
        end
    end
    

  initial begin
        $display("Initializing top, entry point = 0x%x", entry);
  end
    
endmodule
