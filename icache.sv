module Icache
#(
    ID_WIDTH = 13,
    ADDR_WIDTH = 64,
    DATA_WIDTH = 64
)
(
    input clk,
    input reset,
    
    // Pipeline interface
    input  [63:0]   sm_pc,
    output [31:0]   ir,
    output          icache_valid,

    // AXI interface
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
    output  wire                   m_axi_rready
);

    localparam LOG_WORD_LEN = 3; // log(number of bytes in word)
    localparam LINE_LEN = 8; // number of words in line
    localparam LOG_LINE_LEN = 3; // log(number of words in line)

    reg [DATA_WIDTH-1:0] mem [LINE_LEN];
    reg [ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN] line_tag;
    reg line_valid;
    
    reg [2:0] state;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset;

    assign ir = sm_pc[LOG_WORD_LEN-1] ? mem[sm_pc[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN]][63:32] : mem[sm_pc[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN]][31:0];
    assign icache_valid = sm_pc[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN] == line_tag && line_valid;
    assign m_axi_arvalid = state == 3'h1;
    assign m_axi_rready = state == 3'h2;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 3'h0;
            line_valid <= 1'b0;
            
            m_axi_arid <= 0;      // transaction id
            m_axi_araddr <= 0;    // address
            m_axi_arlen <= 8'h7;  // +1, =8 words requested
            m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            m_axi_arlock <= 1'b0; // no lock
            m_axi_arcache <= 4'h0;// no cache
            m_axi_arprot <= 3'h6; // enum, means something
        end else begin
            case(state)
            3'h0: begin  // idle
                // It's addressed by bytes, even though you don't get full granularity at byte level
                m_axi_araddr <= sm_pc;
                if(!icache_valid)
                    state <= 3'h1;
            end
            3'h1: begin // address channel
                line_tag <= m_axi_araddr[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN];
                line_valid <= 1'b0;
                offset <= m_axi_araddr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
                if(m_axi_arready)
                    state <= 3'h2;
            end
            3'h2: begin // data channel
                if(m_axi_rvalid) begin
                    mem[offset] <= m_axi_rdata;
                    offset <= offset + 1;
                    if(m_axi_rlast) begin
                        line_valid <= 1'b1;
                        state <= 3'h0;
                    end
                end
            end
            default: state <= 3'h0;
            endcase
        end
    end
endmodule
