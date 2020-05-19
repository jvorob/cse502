`ifndef ICACHE
`define ICACHE

`include "lru.sv"
`include "CAM.sv"

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
    input  [63:0]   in_fetch_addr,
    input           icache_enable,

    output [31:0]   out_inst,
    output reg      icache_valid,
    

    // Other signals (virtual mode / TLB)
    input           virtual_mode, // determines "in_fetch_addr" is virtual or physical
    input  [63:0]   translated_addr,
    input           translated_addr_valid,

    // AXI interface
    output  wire [ID_WIDTH-1:0]    icache_m_axi_arid,
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
    parameter WORD_LEN = 8; // number of bytes in word
    parameter LOG_WORD_LEN = 3; // log(number of bytes in word)
    parameter LINE_LEN = 8; // number of words in line
    parameter LOG_LINE_LEN = 3; // log(number of words in line)
    parameter SIZE = 16 * 1024; // size of cache in bytes
    parameter WAYS = 4; // 4-way
    parameter SETS = SIZE / (WAYS * LINE_LEN * WORD_LEN); // number of sets in cache
    parameter LOG_SETS = 6; // log(number of sets in cache)
    parameter LRU_LEN = 5; // 5 bit is enough for 4-way

    reg [DATA_WIDTH-1:0] mem [SETS][WAYS][LINE_LEN];
    reg [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] line_tag [SETS][WAYS];
    reg line_valid [SETS][WAYS];
    reg line_prefetched[SETS][WAYS];
    reg [LRU_LEN-1:0] line_lru [SETS];
    
    wire queue_full;
    wire queue_cam_exists;
    wire queue_push = (state == 3'h1 || state == 3'h3) && icache_m_axi_arready && !queue_full;
    wire queue_pop = (receive_state == 1'b1) && icache_m_axi_rvalid && icache_m_axi_rlast;
    wire [1:0] queue_push_index;
    wire [1:0] queue_pop_index = icache_m_axi_rid[1:0];
    wire [ADDR_WIDTH:LOG_LINE_LEN+LOG_WORD_LEN]  queue_data_in = {(state == 3'h3), rplc_pc[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN]};
    wire [ADDR_WIDTH:LOG_LINE_LEN+LOG_WORD_LEN]  queue_data_out;
    wire [ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN] queue_cam_data = (state == 3'h2) ? prefetch_line : fetch_addr[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN];

    reg [2:0] state;
    reg receive_state;
    reg [ADDR_WIDTH-1:0] rplc_pc;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] rplc_offset;
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] rplc_index = queue_data_out[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] rplc_tag = queue_data_out[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    reg [1:0] rplc_way;

    wire [ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN] prefetch_line = rplc_pc[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN] + 1;
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] prefetch_tag = prefetch_line[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] prefetch_index = prefetch_line[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];

    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] snoop_index = icache_m_axi_acaddr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] snoop_tag = icache_m_axi_acaddr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    integer snoop_way;

    wire [ADDR_WIDTH-1:0] fetch_addr = virtual_mode ? {trns_tag, in_fetch_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:0]} : in_fetch_addr;
    wire [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset = fetch_addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] index = fetch_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] tag = fetch_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] trns_tag = translated_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    
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
                icache_valid = !icache_m_axi_acvalid && icache_enable && (!virtual_mode || translated_addr_valid);
                mru = way;
            end
    end

    reg line_exists;
    integer prefetch_way;
    always_comb begin
        line_exists = 1'b0;
        for (prefetch_way = 0; prefetch_way < WAYS; prefetch_way = prefetch_way + 1)
            if (prefetch_tag == line_tag[prefetch_index][prefetch_way] && line_valid[prefetch_index][prefetch_way])
                line_exists = 1'b1;
    end

    always_ff @ (posedge clk) begin
        if (reset)
            line_lru <= '{SETS{5'b0_01_00}}; // 3 2 1 0
        else if (icache_valid)
            line_lru[index] <= new_lru(line_lru[index], mru);
    end

    assign out_inst = fetch_addr[LOG_WORD_LEN-1] ? inst_word[63:32] : inst_word[31:0];
    assign icache_m_axi_arid = queue_push_index;
    assign icache_m_axi_araddr = {rplc_pc[ADDR_WIDTH-1:LOG_LINE_LEN+LOG_WORD_LEN], {LOG_LINE_LEN{1'b0}}, {LOG_WORD_LEN{1'b0}}};
    assign icache_m_axi_arvalid = (state == 3'h1 || state == 3'h3) && !queue_full;
    assign icache_m_axi_rready = receive_state == 1'b1;
    assign icache_m_axi_acready = receive_state == 1'b0;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 3'h0;
            line_prefetched <= '{SETS{'{WAYS{1'b0}}}};
            rplc_pc <= 0;
            
            icache_m_axi_arlen <= 8'h7;  // +1, =8 words requested
            icache_m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            icache_m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            icache_m_axi_arlock <= 1'b0; // no lock
            icache_m_axi_arcache <= 4'h0;// no cache
            icache_m_axi_arprot <= 3'h6; // enum, means something
        end else begin
            case(state)
            3'h0: begin  // idle
                // start a cache miss
                if(!icache_m_axi_acvalid && icache_enable && (!virtual_mode || translated_addr_valid)) begin
                    if (icache_valid) begin
                        if (line_prefetched[index][mru]) begin
                            state <= 3'h2;
                            line_prefetched[index][mru] <= 1'b0;
                            rplc_pc <= fetch_addr;
                        end
                    end else if(!queue_cam_exists) begin
                        state <= 3'h1;
                        rplc_pc <= fetch_addr;
                    end
                end
            end
            3'h1: begin // address channel
                if(icache_m_axi_arready && !queue_full)
                    state <= 3'h2;
            end
            3'h2: begin // prefetch
                if(!line_exists && !queue_cam_exists && prefetch_index != 0) begin
                    state <= 3'h3;
                    rplc_pc <= {prefetch_line, {LOG_LINE_LEN{1'b0}}, {LOG_WORD_LEN{1'b0}}};
                end else
                    state <= 3'h0;
            end
            3'h3: begin // address channel (prefetch next line)
                if(icache_m_axi_arready && !queue_full)
                    state <= 3'h0;
            end
            default: state <= 3'h0;
            endcase
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            receive_state <= 1'b0;
            line_valid <= '{SETS{'{WAYS{1'b0}}}};
            rplc_offset <= 0;
            rplc_way <= 2'h0;
        end else if (receive_state == 1'b0) begin
            if(icache_m_axi_acvalid && (icache_m_axi_acsnoop == 4'hd)) begin // snoop invalidation
                for (snoop_way = 0; snoop_way < WAYS; snoop_way = snoop_way + 1)
                    if(line_tag[snoop_index][snoop_way] == snoop_tag)
                        line_valid[snoop_index][snoop_way] <= 1'b0;
            end else if(icache_m_axi_rvalid) begin
                rplc_offset <= 0;
                rplc_way <= !line_valid[rplc_index][0] ? 2'h0 : !line_valid[rplc_index][1] ? 2'h1 : !line_valid[rplc_index][2] ? 2'h2 : !line_valid[rplc_index][3] ? 2'h3 : line_lru[rplc_index][1:0];
                receive_state <= 1'b1;
            end
        end else begin // receive_state == 1'b1
            if(icache_m_axi_rvalid) begin
                mem[rplc_index][rplc_way][rplc_offset] <= icache_m_axi_rdata;
                line_valid[rplc_index][rplc_way] <= icache_m_axi_rlast;
                rplc_offset <= rplc_offset + 1;
                if(icache_m_axi_rlast) begin
                    line_prefetched[rplc_index][rplc_way] <= queue_data_out[ADDR_WIDTH];
                    line_tag[rplc_index][rplc_way] <= rplc_tag;
                    receive_state <= 1'b0;
                end
            end
        end
    end

    CAM
    #(
        .WIDTH(ADDR_WIDTH-LOG_LINE_LEN-LOG_WORD_LEN+1),
        .CAM_WIDTH(ADDR_WIDTH-LOG_LINE_LEN-LOG_WORD_LEN), 
        .DEPTH(4),
        .LOG_DEPTH(2)
    )
    queue
    (
        .full(queue_full),
        .push(queue_push),
        .pop(queue_pop),
        .push_index(queue_push_index),
        .pop_index(queue_pop_index),
        .data_in(queue_data_in),
        .data_out(queue_data_out),
        .cam_data(queue_cam_data),
        .cam_exists(queue_cam_exists),
        .*
    );

endmodule

`endif
