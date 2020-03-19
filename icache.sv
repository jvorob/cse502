`include "lru.sv"

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
    input  [63:0]   fetch_addr,
    output [31:0]   out_inst,
    output reg      icache_valid,

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
    output  wire                   icache_m_axi_rready,
    input   wire                   icache_m_axi_acvalid,
    output  wire                   icache_m_axi_acready,
    input   wire [ADDR_WIDTH-1:0]  icache_m_axi_acaddr,
    input   wire [3:0]             icache_m_axi_acsnoop
);
    localparam WORD_LEN = 8; // number of bytes in word
    localparam LOG_WORD_LEN = 3; // log(number of bytes in word)
    localparam LINE_LEN = 8; // number of words in line
    localparam LOG_LINE_LEN = 3; // log(number of words in line)
    localparam SIZE = 16 * 1024; // size of cache in bytes
    localparam WAYS = 4; // 4-way
    localparam SETS = SIZE / (WAYS * LINE_LEN * WORD_LEN); // number of sets in cache
    localparam LOG_SETS = 6; // log(number of sets in cache)
    localparam LRU_LEN = 5; // 5 bit is enough for 4-way

    reg [DATA_WIDTH-1:0] mem [SETS][WAYS][LINE_LEN];
    reg [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] line_tag [SETS][WAYS];
    reg line_valid [SETS][WAYS];
    reg [LRU_LEN-1:0] line_lru [SETS];
    
    reg [2:0] state;
    reg [63:0] rplc_pc;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] rplc_offset;
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] rplc_index = rplc_pc[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] rplc_tag = rplc_pc[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    reg [1:0] rplc_way;

    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] snoop_index = icache_m_axi_acaddr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] snoop_tag = icache_m_axi_acaddr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    integer snoop_way;

    wire [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset = fetch_addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] index = fetch_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] tag = fetch_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    
    reg [DATA_WIDTH-1:0] inst_word;
    integer way;
    integer mru;
    always_comb begin
        inst_word = mem[index][0][offset];
        icache_valid = 1'b0;
        mru = 0;
        for (way = 0; way < WAYS; way = way + 1) 
            if (tag == line_tag[index][way] && line_valid[index][way]) begin
                inst_word = mem[index][way][offset];
                icache_valid = !icache_m_axi_acvalid;
                mru = way;
            end
    end

    always_ff @ (posedge clk) begin
        if (reset)
            line_lru <= '{SETS{5'b0_01_00}}; // 3 2 1 0
        else if (icache_valid)
            line_lru[index] <= new_lru(line_lru[index], mru);
    end

    assign out_inst = fetch_addr[LOG_WORD_LEN-1] ? inst_word[63:32] : inst_word[31:0];
    assign icache_m_axi_araddr = {rplc_pc[ADDR_WIDTH-1:LOG_WORD_LEN], {LOG_WORD_LEN{1'b0}}};
    assign icache_m_axi_acready = state == 3'h0;
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
                rplc_pc <= fetch_addr;
                rplc_way <= !line_valid[index][0] ? 2'h0 : !line_valid[index][1] ? 2'h1 : !line_valid[index][2] ? 2'h2 : !line_valid[index][3] ? 2'h3 : line_lru[index][1:0];
                if(icache_m_axi_acvalid && (icache_m_axi_acsnoop == 4'hd)) begin // snoop invalidation
                    for (snoop_way = 0; snoop_way < WAYS; snoop_way = snoop_way + 1)
                        if(line_tag[snoop_index][snoop_way] == snoop_tag)
                            line_valid[snoop_index][snoop_way] <= 1'b0;
                end else if(!icache_valid)
                    state <= 3'h1;
            end
            3'h1: begin // address channel
               // $display("icache fetch request addr: %x", icache_m_axi_araddr);
                line_tag[rplc_index][rplc_way] <= rplc_tag;
                line_valid[rplc_index][rplc_way] <= 1'b0;
                rplc_offset <= rplc_pc[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
                if(icache_m_axi_arready)
                    state <= 3'h2;
            end
            3'h2: begin // data channel
                if(icache_m_axi_rvalid) begin
                    mem[rplc_index][rplc_way][rplc_offset] <= icache_m_axi_rdata;
                    rplc_offset <= rplc_offset + 1;
                    if(icache_m_axi_rlast) begin
                        line_valid[rplc_index][rplc_way] <= 1'b1;
                        state <= 3'h0;
                    end
                end
            end
            default: state <= 3'h0;
            endcase
        end
    end

endmodule
