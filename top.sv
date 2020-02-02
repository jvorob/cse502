`include "Sysbus.defs"

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
	

  // Values of F3 for various ops
  typedef enum bit[2:0] {
    F3OP_ADD //TODO
  } Funct3_Op;

  // Values of F3 for branches
  typedef enum bit[2:0] {
    F3B_BEQ  = 3'b000,
    F3B_BNE  = 3'b001,
    F3B_BLT  = 3'b100,
    F3B_BGE  = 3'b101,
    F3B_BLTU = 3'b110,
    F3B_BGEU = 3'b111
  } Funct3_Branch;

	function void decode(input logic[31:0] inst);

    Opcode op = inst[6:0];

    // There's 5 different kinds of immediates: I, S, SB, U, UJ
    // NOTE: When immediates need to be sign-extended,
    //       you can always take sign from inst[31]
    logic [11:0]  immed_I  = inst[31:20];
    logic [11:0]  immed_S  = { inst[31:                   25], inst[11:        7] };
    logic [12:0]  immed_SB = { inst[31], inst[7], inst[30:25], inst[11:8],   1'b0 };
    logic [31:0]  immed_U  = { inst[31:          12],                       12'b0 };
    logic [20:0]  immed_UJ = { inst[31], inst[19:12], inst[20], inst[30:24], 1'b0 } ;

    logic [4:0] rs1 = inst[19:15];
    logic [4:0] rs2 = inst[24:20];
    logic [4:0] rd  = inst[11: 7];
    logic [2:0] funct3 = inst[14:12];
    logic [6:0] funct7 = inst[31:25];

    $display("\n");
    $display("Decoding instruction %b ", inst);
    $display("got opcode %s ('%b\')", op.name(), op);

    case (op) inside
      OP_LUI: begin
        $display("LUI 0x%x to r%0d'", immed_U, rd);
      end
      OP_AUIPC: begin
        $display("AUIPC 0x%x to r%0d'", immed_U, rd);
      end
      OP_JAL: begin
        $display("JAL 0x%x, return addr in r%0d'", immed_UJ, rd);
      end
      OP_JALR: begin
        if (funct3 != 3'b000) $error("ERROR: Invalid funct3 for JALR op, '%b'", funct3);
        $display("JALR r%0d+0x%x, return addr in r%0d'", rs1, immed_I, rd);
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
      end
      OP_STORE: begin
        //TODO --Jan
      end
      OP_OP_IMM: begin
        //TODO --Jan
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
