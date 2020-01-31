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
	
	function void decode(input logic[31:0] instruc);
		if (0 == 1) begin
			$display("First instruction");
		end
		else if (0 == 1) begin
			$display("Second instruction");
		end
		else begin
			$display("Not recognized instruction.");
		end
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
                    $display("Hello");
                    m_axi_araddr <= pc[63:3];
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
