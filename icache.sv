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
    output  reg  [ID_WIDTH-1:0]    icache_m_axi_arid,
    output  wire [ADDR_WIDTH-1:0]  icache_m_axi_araddr,
    output  reg  [7:0]             icache_m_axi_arlen,
    output  reg  [2:0]             icache_m_axi_arsize,
    output  reg  [1:0]             icache_m_axi_arburst,
    output  reg                    icache_m_axi_arlock,
    output  reg  [3:0]             icache_m_axi_arcache,
    output  reg  [2:0]             icache_m_axi_arprot,
    output  wire                   icache_m_axi_arvalid,
    input   wire                   icache_m_axi_arready,
    input   wire [ID_WIDTH-1:0]    icache_m_axi_rid,
    input   wire [DATA_WIDTH-1:0]  icache_m_axi_rdata,
    input   wire [1:0]             icache_m_axi_rresp,
    input   wire                   icache_m_axi_rlast,
    input   wire                   icache_m_axi_rvalid,
    output  wire                   icache_m_axi_rready
);
    localparam WORD_LEN = 8; // number of bytes in word
    localparam LOG_WORD_LEN = 3; // log(number of bytes in word)
    localparam LINE_LEN = 8; // number of words in line
    localparam LOG_LINE_LEN = 3; // log(number of words in line)
    localparam SIZE = 16 * 1024; // size of cache in bytes
    localparam WAYS = 1; // direct map
    localparam SETS = SIZE / (WAYS * LINE_LEN * WORD_LEN); // number of sets in cache
    localparam LOG_SETS = 8; // log(number of sets in cache)

    reg [DATA_WIDTH-1:0] mem [SETS][WAYS][LINE_LEN];
    reg [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] line_tag [SETS][WAYS];
    reg line_valid [SETS][WAYS];
    
    reg [2:0] state;
    reg [63:0] rplc_pc;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] rplc_offset;
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] rplc_index = rplc_pc[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] rplc_tag = rplc_pc[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    wire [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset = sm_pc[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] index = sm_pc[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] tag = sm_pc[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    assign ir = sm_pc[LOG_WORD_LEN-1] ? mem[index][0][offset][63:32] : mem[index][0][offset][31:0];
    assign icache_valid = tag == line_tag[index][0] && line_valid[index][0];
    assign icache_m_axi_araddr = rplc_pc;
    assign icache_m_axi_arvalid = state == 3'h1;
    assign icache_m_axi_rready = state == 3'h2;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 3'h0;
            line_valid <= '{SETS{'{WAYS{1'b0}}}};
            rplc_pc <= 0;
            
            icache_m_axi_arid <= 0;      // transaction id
            icache_m_axi_arlen <= 8'h7;  // +1, =8 words requested
            icache_m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            icache_m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            icache_m_axi_arlock <= 1'b0; // no lock
            icache_m_axi_arcache <= 4'h0;// no cache
            icache_m_axi_arprot <= 3'h6; // enum, means something
        end else begin
            case(state)
            3'h0: begin  // idle
                // It's addressed by bytes, even though you don't get full granularity at byte level
                rplc_pc <= sm_pc;
                if(!icache_valid)
                    state <= 3'h1;
            end
            3'h1: begin // address channel
                line_tag[rplc_index][0] <= rplc_tag;
                line_valid[rplc_index][0] <= 1'b0;
                rplc_offset <= rplc_pc[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
                if(icache_m_axi_arready)
                    state <= 3'h2;
            end
            3'h2: begin // data channel
                if(icache_m_axi_rvalid) begin
                    mem[rplc_index][0][rplc_offset] <= icache_m_axi_rdata;
                    rplc_offset <= rplc_offset + 1;
                    if(icache_m_axi_rlast) begin
                        line_valid[rplc_index][0] <= 1'b1;
                        state <= 3'h0;
                    end
                end
            end
            default: state <= 3'h0;
            endcase
        end
    end
endmodule
