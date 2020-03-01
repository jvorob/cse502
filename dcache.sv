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
    input  [63:0]   addr,
    input  [63:0]   wdata,
    input  [ 1:0]   wlen, // len = 2 ^ wlen bytes
    input           dcache_enable,
    input           wrn, // write = 1 / read = 0
    output [63:0]   rdata,
    output          dcache_valid,
    output          write_done,

    // AXI interface
    output  reg  [ID_WIDTH-1:0]     dcache_m_axi_awid,
    output  wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr,
    output  reg  [7:0]              dcache_m_axi_awlen,
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
    output  reg  [7:0]              dcache_m_axi_arlen,
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
    output  wire                    dcache_m_axi_rready
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
    reg line_dirty [SETS][WAYS];
    
    reg [2:0] state;
    reg [63:0] rplc_addr;
    reg [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] rplc_offset;
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] rplc_index = rplc_addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] rplc_tag = rplc_addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    wire [LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN] offset = addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
    wire [LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN] index = addr[LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_LINE_LEN+LOG_WORD_LEN];
    wire [ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN] tag = addr[ADDR_WIDTH-1:LOG_SETS+LOG_LINE_LEN+LOG_WORD_LEN];

    assign rdata = mem[index][0][offset];
    assign dcache_valid = dcache_enable && !wrn && tag == line_tag[index][0] && line_valid[index][0];
    assign write_done = state == 3'h0 && dcache_enable && wrn && tag == line_tag[index][0] && line_valid[index][0];
    assign dcache_m_axi_araddr = rplc_addr;
    assign dcache_m_axi_awaddr = {line_tag[rplc_index][0], rplc_index, {LOG_LINE_LEN{1'b0}}, {LOG_WORD_LEN{1'b0}}};
    assign dcache_m_axi_wdata = mem[rplc_index][0][rplc_offset];
    assign dcache_m_axi_awvalid = state == 3'h1;
    assign dcache_m_axi_wvalid = state == 3'h2;
    assign dcache_m_axi_arvalid = state == 3'h3;
    assign dcache_m_axi_rready = state == 3'h4;
    assign dcache_m_axi_wlast = rplc_offset == {LOG_LINE_LEN{1'b1}};

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 3'h0;
            line_valid <= '{SETS{'{WAYS{1'b0}}}};
            line_dirty <= '{SETS{'{WAYS{1'b0}}}};
            rplc_addr <= 0;
            
            dcache_m_axi_arid <= 1;      // transaction id
            dcache_m_axi_arlen <= 8'h7;  // +1, =8 words requested
            dcache_m_axi_arsize <= 3'h3; // 2^3, word width is 8 bytes
            dcache_m_axi_arburst <= 2'h2;// 2 in enum, bursttype=wrap
            dcache_m_axi_arlock <= 1'b0; // no lock
            dcache_m_axi_arcache <= 4'h0;// no cache
            dcache_m_axi_arprot <= 3'h6; // enum, means something
            dcache_m_axi_awid <= 1;      // transaction id
            dcache_m_axi_awlen <= 8'h7;  // +1, =8 words requested
            dcache_m_axi_awsize <= 3'h3; // 2^3, word width is 8 bytes
            dcache_m_axi_awburst <= 2'h1;// 1 in enum, bursttype=incr
            dcache_m_axi_awlock <= 1'b0; // no lock
            dcache_m_axi_awcache <= 4'h0;// no cache
            dcache_m_axi_awprot <= 3'h6; // enum, means something
            dcache_m_axi_wstrb <= {STRB_WIDTH{1'b1}};
            dcache_m_axi_bready <= 1'b1;
        end else begin
            case(state)
            3'h0: begin // idle
                if(dcache_enable) begin
                    rplc_addr <= addr;
                    if(tag == line_tag[index][0] && line_valid[index][0]) begin // hit
                        if(wrn) begin // write
                            case(wlen)
                            3'h0: mem[index][0][offset][8*addr[LOG_WORD_LEN-1:0]+:8] <= wdata;
                            3'h1: mem[index][0][offset][16*addr[LOG_WORD_LEN-1:1]+:16] <= wdata;
                            3'h2: mem[index][0][offset][32*addr[LOG_WORD_LEN-1]+:32] <= wdata;
                            3'h3: mem[index][0][offset] <= wdata;
                            endcase
                            line_dirty[index][0] <= 1'b1;
                        end
                    end else if(line_valid[index][0] && line_dirty[index][0]) // miss needs write back
                        state <= 3'h1;
                    else // miss no need to write back
                        state <= 3'h3;
                end
            end
            3'h1: begin // write back address channel
                rplc_offset <= 0;
                if(dcache_m_axi_awready)
                    state <= 3'h2;
            end
            3'h2: begin // write back data channel
                if(dcache_m_axi_wready) begin
                    rplc_offset <= rplc_offset + 1;
                    if(dcache_m_axi_wlast) begin
                        line_dirty[rplc_index][0] <= 1'b0;
                        state <= 3'h3;
                    end
                end
            end
            3'h3: begin // address channel
                line_tag[rplc_index][0] <= rplc_tag;
                line_valid[rplc_index][0] <= 1'b0;
                rplc_offset <= rplc_addr[LOG_LINE_LEN+LOG_WORD_LEN-1:LOG_WORD_LEN];
                if(dcache_m_axi_arready)
                    state <= 3'h4;
            end
            3'h4: begin // data channel
                if(dcache_m_axi_rvalid) begin
                    mem[rplc_index][0][rplc_offset] <= dcache_m_axi_rdata;
                    rplc_offset <= rplc_offset + 1;
                    if(dcache_m_axi_rlast) begin
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
