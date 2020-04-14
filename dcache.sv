`ifndef DCACHE
`define DCACHE

`include "lru.sv"

module Dcache
#(
    ID_WIDTH = 13,
    ADDR_WIDTH = 64,
    DATA_WIDTH = 64,
    STRB_WIDTH = DATA_WIDTH/8
)
(
    input  clk,
    input  reset,
    
    // Pipeline interface
    input        [63:0]   in_addr,
    input        [63:0]   wdata,
    input        [ 1:0]   wlen, // len = 2 ^ wlen bytes
    input                 dcache_enable,
    input                 wrn, // write = 1 / read = 0
    input                 virtual_mode, // determines "in_addr" is virtual or physical
    output  reg  [63:0]   rdata,
    output  reg           dcache_valid,
    output  reg           write_done,

    input        [63:0]   translated_addr,
    input                 translated_addr_valid,

    // AXI interface
    output  reg  [ID_WIDTH-1:0]     dcache_m_axi_awid,
    output  wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr,
    output  wire [7:0]              dcache_m_axi_awlen,
    output  reg  [2:0]              dcache_m_axi_awsize,
    output  reg  [1:0]              dcache_m_axi_awburst,
    output  reg                     dcache_m_axi_awlock,
    output  reg  [3:0]              dcache_m_axi_awcache,
    output  reg  [2:0]              dcache_m_axi_awprot,
    output  wire                    dcache_m_axi_awvalid,
    input   wire                    dcache_m_axi_awready,
    output  wire [DATA_WIDTH-1:0]   dcache_m_axi_wdata,
    output  reg  [STRB_WIDTH-1:0]   dcache_m_axi_wstrb,
    output  wire                    dcache_m_axi_wlast,
    output  wire                    dcache_m_axi_wvalid,
    input   wire                    dcache_m_axi_wready,
    input   wire [ID_WIDTH-1:0]     dcache_m_axi_bid,
    input   wire [1:0]              dcache_m_axi_bresp,
    input   wire                    dcache_m_axi_bvalid,
    output  reg                     dcache_m_axi_bready,
    output  reg  [ID_WIDTH-1:0]     dcache_m_axi_arid,
    output  wire [ADDR_WIDTH-1:0]   dcache_m_axi_araddr,
    output  wire [7:0]              dcache_m_axi_arlen,
    output  reg  [2:0]              dcache_m_axi_arsize,
    output  reg  [1:0]              dcache_m_axi_arburst,
    output  reg                     dcache_m_axi_arlock,
    output  reg  [3:0]              dcache_m_axi_arcache,
    output  reg  [2:0]              dcache_m_axi_arprot,
    output  wire                    dcache_m_axi_arvalid,
    input   wire                    dcache_m_axi_arready,
    input   wire [ID_WIDTH-1:0]     dcache_m_axi_rid,
    input   wire [DATA_WIDTH-1:0]   dcache_m_axi_rdata,
    input   wire [1:0]              dcache_m_axi_rresp,
    input   wire                    dcache_m_axi_rlast,
    input   wire                    dcache_m_axi_rvalid,
    output  wire                    dcache_m_axi_rready,
    input   wire                    dcache_m_axi_acvalid,
    output  wire                    dcache_m_axi_acready,
    input   wire [ADDR_WIDTH-1:0]   dcache_m_axi_acaddr,
    input   wire [3:0]              dcache_m_axi_acsnoop
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

    parameter RAM_START = 64'h0000000080000000;

    reg [DATA_WIDTH-1:0] mem [SETS][WAYS][LINE_LEN];
    reg [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] line_tag [SETS][WAYS];
    reg line_valid [SETS][WAYS];
    reg line_dirty [SETS][WAYS];
    reg [LRU_LEN-1:0] line_lru [SETS];
    
    reg [3:0] state;
    reg [63:0] rplc_addr;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] rplc_offset;
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] rplc_index = rplc_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] rplc_tag = rplc_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    wire [1:0] victim_way = !line_valid[index][0] ? 2'h0 : !line_valid[index][1] ? 2'h1 : !line_valid[index][2] ? 2'h2 : !line_valid[index][3] ? 2'h3 : line_lru[index][1:0];
    reg [1:0] rplc_way;

    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] snoop_index = dcache_m_axi_acaddr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] snoop_tag = dcache_m_axi_acaddr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];
    integer snoop_way;

    wire [ADDR_WIDTH-1:0] addr = virtual_mode ? {trns_tag, in_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:0]} : in_addr;
    wire [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset = addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] index = addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] tag = addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] trns_tag = translated_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    wire isIO = addr < RAM_START;
    reg [DATA_WIDTH-1:0] IO_reg;

    always_comb begin
        if (state == 4'h2)
            dcache_m_axi_wstrb = 8'hff;
        else if (state == 4'h6)
            case(wlen)
            2'h0: dcache_m_axi_wstrb = 8'h01 << addr[LOG_WORD_LEN-1:0];
            2'h1: dcache_m_axi_wstrb = 8'h03 << 2*addr[LOG_WORD_LEN-1:1];
            2'h2: dcache_m_axi_wstrb = 8'h0f << 4*addr[LOG_WORD_LEN-1];
            2'h3: dcache_m_axi_wstrb = 8'hff;
            endcase
        else
            dcache_m_axi_wstrb = 8'h00;
    end

    integer way;
    integer mru;
    always_comb begin
        rdata = 0;
        dcache_valid = 1'b0;
        write_done = 1'b0;
        mru = 0;
        if (isIO) begin
            rdata = dcache_m_axi_rdata;
            dcache_valid = (state == 4'h8) && dcache_m_axi_rvalid;
            write_done = (state == 4'h6) && dcache_m_axi_wready;
        end else begin
            rdata = mem[index][0][offset];
            for (way = 0; way < WAYS; way = way + 1)
                if (tag == line_tag[index][way] && line_valid[index][way]) begin
                    rdata = mem[index][way][offset];
                    dcache_valid = !dcache_m_axi_acvalid && dcache_enable && (!virtual_mode || translated_addr_valid) && !wrn;
                    write_done = state == 4'h0 && !dcache_m_axi_acvalid && dcache_enable && (!virtual_mode || translated_addr_valid) && wrn;
                    mru = way;
                end
        end
    end

    always_ff @ (posedge clk) begin
        if (reset)
            line_lru <= '{SETS{5'b0_01_00}}; // 3 2 1 0
        else if (dcache_valid || write_done)
            line_lru[index] <= new_lru(line_lru[index], mru);
    end

    assign dcache_m_axi_araddr = {rplc_addr[ADDR_WIDTH-1:LOG_WORD_LEN], {LOG_WORD_LEN{1'b0}}};
    assign dcache_m_axi_awaddr = (state == 4'h1) ? {line_tag[rplc_index][rplc_way], rplc_index, {LOG_LINE_LEN{1'b0}}, {LOG_WORD_LEN{1'b0}}} : (state == 4'h5) ? {rplc_addr[ADDR_WIDTH-1:LOG_WORD_LEN], {LOG_WORD_LEN{1'b0}}} : 0;
    assign dcache_m_axi_wdata = (state == 4'h2) ? mem[rplc_index][rplc_way][rplc_offset] : (state == 4'h6) ? IO_reg : 0;
    assign dcache_m_axi_acready = state == 4'h0;
    assign dcache_m_axi_awvalid = (state == 4'h1) || (state == 4'h5);
    assign dcache_m_axi_wvalid = (state == 4'h2) || (state == 4'h6);
    assign dcache_m_axi_arvalid = (state == 4'h3) || (state == 4'h7);
    assign dcache_m_axi_rready = (state == 4'h4) || (state == 4'h8);
    assign dcache_m_axi_wlast = (state == 4'h2) ? (rplc_offset == {LOG_LINE_LEN{1'b1}}) : (state == 4'h6) ? 1'b1 : 1'b0;
    assign dcache_m_axi_awlen = (state == 4'h1) ? 8'h7 : (state == 4'h5) ? 8'h0 : 8'h0;  // +1 words requested
    assign dcache_m_axi_arlen = (state == 4'h3) ? 8'h7 : (state == 4'h7) ? 8'h0 : 8'h0;  // +1 words requested

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 4'h0;
            line_valid <= '{SETS{'{WAYS{1'b0}}}};
            line_dirty <= '{SETS{'{WAYS{1'b0}}}};
            rplc_addr <= 0;
            IO_reg <= 0;
            
            dcache_m_axi_arid <= 1;      // transaction id
            dcache_m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            dcache_m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            dcache_m_axi_arlock <= 1'b0; // no lock
            dcache_m_axi_arcache <= 4'h0;// no cache
            dcache_m_axi_arprot <= 3'h6; // enum, means something
            dcache_m_axi_awid <= 1;      // transaction id
            dcache_m_axi_awsize <= 3'h3; // 2^3, word width is 8 bytes
            dcache_m_axi_awburst <= 2'h1;// 1 in enum, bursttype=incr
            dcache_m_axi_awlock <= 1'b0; // no lock
            dcache_m_axi_awcache <= 4'h0;// no cache
            dcache_m_axi_awprot <= 3'h6; // enum, means something
            dcache_m_axi_bready <= 1'b1;
        end else begin
            case(state)
            4'h0: begin // idle
                if(dcache_m_axi_acvalid && (dcache_m_axi_acsnoop == 4'hd)) begin // snoop invalidation
                    for (snoop_way = 0; snoop_way < WAYS; snoop_way = snoop_way + 1)
                        if(line_tag[snoop_index][snoop_way] == snoop_tag) begin
                            line_valid[snoop_index][snoop_way] <= 1'b0;
                            line_dirty[snoop_index][snoop_way] <= 1'b0;
                        end
                end else if(dcache_enable && (!virtual_mode || translated_addr_valid)) begin
                    rplc_addr <= addr;
                    if(isIO) begin
                        if(wrn) begin // IO write
                            case(wlen)
                            2'h0: IO_reg <= wdata << 8*addr[LOG_WORD_LEN-1:0];
                            2'h1: IO_reg <= wdata << 16*addr[LOG_WORD_LEN-1:1];
                            2'h2: IO_reg <= wdata << 32*addr[LOG_WORD_LEN-1];
                            2'h3: IO_reg <= wdata;
                            endcase
                            state <= 4'h5;
                        end else // IO read
                            state <= 4'h7;
                    end else begin
                        rplc_way <= victim_way;
                        if(dcache_valid || write_done) begin // hit
                            if(write_done) begin // write
                                case(wlen)
                                2'h0: mem[index][mru][offset][8*addr[LOG_WORD_LEN-1:0]+:8] <= wdata;
                                2'h1: mem[index][mru][offset][16*addr[LOG_WORD_LEN-1:1]+:16] <= wdata;
                                2'h2: mem[index][mru][offset][32*addr[LOG_WORD_LEN-1]+:32] <= wdata;
                                2'h3: mem[index][mru][offset] <= wdata;
                                endcase

                                // Also notify do_pending_write to make Mike's ecall hacks work 
                                case(wlen)
                                2'h0: do_pending_write(addr, wdata, 1);
                                2'h1: do_pending_write({addr[ADDR_WIDTH-1:1], 1'b0}, wdata, 2);
                                2'h2: do_pending_write({addr[ADDR_WIDTH-1:2], 2'b00}, wdata, 4);
                                2'h3: do_pending_write({addr[ADDR_WIDTH-1:3], 3'b000}, wdata, 8);
                                endcase

                                line_dirty[index][mru] <= 1'b1;
                            end
                        end else if(line_valid[index][victim_way] && line_dirty[index][victim_way]) // miss needs write back
                            state <= 4'h1;
                        else // miss no need to write back
                            state <= 4'h3;
                    end
                end
            end
            4'h1: begin // write back address channel
                //$display("dcache write-back request addr: %x", dcache_m_axi_awaddr);
                rplc_offset <= 0;
                if(dcache_m_axi_awready)
                    state <= 4'h2;
            end
            4'h2: begin // write back data channel
                if(dcache_m_axi_wready) begin
                    //$display("dcache write-back offset: %x, data: %x", rplc_offset, dcache_m_axi_wdata);
                    rplc_offset <= rplc_offset + 1;
                    if(dcache_m_axi_wlast) begin
                        line_dirty[rplc_index][rplc_way] <= 1'b0;
                        state <= 4'h3;
                    end
                end
            end
            4'h3: begin // address channel
                //$display("dcache fetch request addr: %x", dcache_m_axi_araddr);
                line_tag[rplc_index][rplc_way] <= rplc_tag;
                line_valid[rplc_index][rplc_way] <= 1'b0;
                rplc_offset <= rplc_addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
                if(dcache_m_axi_arready)
                    state <= 4'h4;
            end
            4'h4: begin // data channel
                if(dcache_m_axi_rvalid) begin
                    //$display("dcache fetch offset: %x, data: %x", rplc_offset, dcache_m_axi_rdata);
                    mem[rplc_index][rplc_way][rplc_offset] <= dcache_m_axi_rdata;
                    rplc_offset <= rplc_offset + 1;
                    if(dcache_m_axi_rlast) begin
                        line_valid[rplc_index][rplc_way] <= 1'b1;
                        state <= 4'h0;
                    end
                end
            end
            4'h5: begin // IO write address channel
                if(dcache_m_axi_awready)
                    state <= 4'h6;
            end
            4'h6: begin // IO write data channel
                if(dcache_m_axi_wready)
                    state <= 4'h0;
            end
            4'h7: begin // IO read address channel
                if(dcache_m_axi_arready)
                    state <= 4'h8;
            end
            4'h8: begin // IO read data channel
                if(dcache_m_axi_rvalid)
                    state <= 4'h0;
            end
            default: state <= 4'h0;
            endcase
        end
    end
endmodule

`endif
