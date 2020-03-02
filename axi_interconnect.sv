module AXI_interconnect
#(
    ID_WIDTH = 13,
    ADDR_WIDTH = 64,
    DATA_WIDTH = 64,
    STRB_WIDTH = DATA_WIDTH/8
)
(
    // bus interface
    output  wire [ID_WIDTH-1:0]     m_axi_awid,
    output  wire [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output  wire [7:0]              m_axi_awlen,
    output  wire [2:0]              m_axi_awsize,
    output  wire [1:0]              m_axi_awburst,
    output  wire                    m_axi_awlock,
    output  wire [3:0]              m_axi_awcache,
    output  wire [2:0]              m_axi_awprot,
    output  wire                    m_axi_awvalid,
    input   wire                    m_axi_awready,
    output  wire [DATA_WIDTH-1:0]   m_axi_wdata,
    output  wire [STRB_WIDTH-1:0]   m_axi_wstrb,
    output  wire                    m_axi_wlast,
    output  wire                    m_axi_wvalid,
    input   wire                    m_axi_wready,
    input   wire [ID_WIDTH-1:0]     m_axi_bid,
    input   wire [1:0]              m_axi_bresp,
    input   wire                    m_axi_bvalid,
    output  wire                    m_axi_bready,
    output  wire [ID_WIDTH-1:0]     m_axi_arid,
    output  wire [ADDR_WIDTH-1:0]   m_axi_araddr,
    output  wire [7:0]              m_axi_arlen,
    output  wire [2:0]              m_axi_arsize,
    output  wire [1:0]              m_axi_arburst,
    output  wire                    m_axi_arlock,
    output  wire [3:0]              m_axi_arcache,
    output  wire [2:0]              m_axi_arprot,
    output  wire                    m_axi_arvalid,
    input   wire                    m_axi_arready,
    input   wire [ID_WIDTH-1:0]     m_axi_rid,
    input   wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input   wire [1:0]              m_axi_rresp,
    input   wire                    m_axi_rlast,
    input   wire                    m_axi_rvalid,
    output  wire                    m_axi_rready,

    // icache interface
    input   wire [ID_WIDTH-1:0]     icache_m_axi_arid,
    input   wire [ADDR_WIDTH-1:0]   icache_m_axi_araddr,
    input   wire [7:0]              icache_m_axi_arlen,
    input   wire [2:0]              icache_m_axi_arsize,
    input   wire [1:0]              icache_m_axi_arburst,
    input   wire                    icache_m_axi_arlock,
    input   wire [3:0]              icache_m_axi_arcache,
    input   wire [2:0]              icache_m_axi_arprot,
    input   wire                    icache_m_axi_arvalid,
    output  wire                    icache_m_axi_arready,
    output  wire [ID_WIDTH-1:0]     icache_m_axi_rid,
    output  wire [DATA_WIDTH-1:0]   icache_m_axi_rdata,
    output  wire [1:0]              icache_m_axi_rresp,
    output  wire                    icache_m_axi_rlast,
    output  wire                    icache_m_axi_rvalid,
    input   wire                    icache_m_axi_rready,

    // dcache interface
    input   wire [ID_WIDTH-1:0]     dcache_m_axi_awid,
    input   wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr,
    input   wire [7:0]              dcache_m_axi_awlen,
    input   wire [2:0]              dcache_m_axi_awsize,
    input   wire [1:0]              dcache_m_axi_awburst,
    input   wire                    dcache_m_axi_awlock,
    input   wire [3:0]              dcache_m_axi_awcache,
    input   wire [2:0]              dcache_m_axi_awprot,
    input   wire                    dcache_m_axi_awvalid,
    output  wire                    dcache_m_axi_awready,
    input   wire [DATA_WIDTH-1:0]   dcache_m_axi_wdata,
    input   wire [STRB_WIDTH-1:0]   dcache_m_axi_wstrb,
    input   wire                    dcache_m_axi_wlast,
    input   wire                    dcache_m_axi_wvalid,
    output  wire                    dcache_m_axi_wready,
    output  wire [ID_WIDTH-1:0]     dcache_m_axi_bid,
    output  wire [1:0]              dcache_m_axi_bresp,
    output  wire                    dcache_m_axi_bvalid,
    input   wire                    dcache_m_axi_bready,
    input   wire [ID_WIDTH-1:0]     dcache_m_axi_arid,
    input   wire [ADDR_WIDTH-1:0]   dcache_m_axi_araddr,
    input   wire [7:0]              dcache_m_axi_arlen,
    input   wire [2:0]              dcache_m_axi_arsize,
    input   wire [1:0]              dcache_m_axi_arburst,
    input   wire                    dcache_m_axi_arlock,
    input   wire [3:0]              dcache_m_axi_arcache,
    input   wire [2:0]              dcache_m_axi_arprot,
    input   wire                    dcache_m_axi_arvalid,
    output  wire                    dcache_m_axi_arready,
    output  wire [ID_WIDTH-1:0]     dcache_m_axi_rid,
    output  wire [DATA_WIDTH-1:0]   dcache_m_axi_rdata,
    output  wire [1:0]              dcache_m_axi_rresp,
    output  wire                    dcache_m_axi_rlast,
    output  wire                    dcache_m_axi_rvalid,
    input   wire                    dcache_m_axi_rready
);

    // adress write channel
    assign m_axi_awid = dcache_m_axi_awid;
    assign m_axi_awaddr = dcache_m_axi_awaddr;
    assign m_axi_awlen = dcache_m_axi_awlen;
    assign m_axi_awsize = dcache_m_axi_awsize;
    assign m_axi_awburst = dcache_m_axi_awburst;
    assign m_axi_awlock = dcache_m_axi_awlock;
    assign m_axi_awcache = dcache_m_axi_awcache;
    assign m_axi_awprot = dcache_m_axi_awprot;
    assign m_axi_awvalid = dcache_m_axi_awvalid;
    assign dcache_m_axi_awready = m_axi_awready;

    // write channel
    assign m_axi_wdata = dcache_m_axi_wdata;
    assign m_axi_wstrb = dcache_m_axi_wstrb;
    assign m_axi_wlast = dcache_m_axi_wlast;
    assign m_axi_wvalid = dcache_m_axi_wvalid;
    assign dcache_m_axi_wready = m_axi_wready;

    // b channel
    assign dcache_m_axi_bid = m_axi_bid;
    assign dcache_m_axi_bresp = m_axi_bresp;
    assign dcache_m_axi_bvalid = m_axi_bvalid;
    assign m_axi_bready = dcache_m_axi_bready;

    // address read channel
    assign m_axi_arid = icache_m_axi_arvalid ? icache_m_axi_arid : dcache_m_axi_arid;
    assign m_axi_araddr = icache_m_axi_arvalid ? icache_m_axi_araddr : dcache_m_axi_araddr;
    assign m_axi_arlen = icache_m_axi_arvalid ? icache_m_axi_arlen : dcache_m_axi_arlen;
    assign m_axi_arsize = icache_m_axi_arvalid ? icache_m_axi_arsize : dcache_m_axi_arsize;
    assign m_axi_arburst = icache_m_axi_arvalid ? icache_m_axi_arburst : dcache_m_axi_arburst;
    assign m_axi_arlock = icache_m_axi_arvalid ? icache_m_axi_arlock : dcache_m_axi_arlock;
    assign m_axi_arcache = icache_m_axi_arvalid ? icache_m_axi_arcache : dcache_m_axi_arcache;
    assign m_axi_arprot = icache_m_axi_arvalid ? icache_m_axi_arprot : dcache_m_axi_arprot;
    assign m_axi_arvalid = icache_m_axi_arvalid | dcache_m_axi_arvalid;
    assign icache_m_axi_arready = icache_m_axi_arvalid ? m_axi_arready : 1'b0;
    assign dcache_m_axi_arready = icache_m_axi_arvalid ? 1'b0 : m_axi_arready;

    // read channel
    assign icache_m_axi_rid = m_axi_rid;
    assign dcache_m_axi_rid = m_axi_rid;
    assign icache_m_axi_rdata = m_axi_rdata;
    assign dcache_m_axi_rdata = m_axi_rdata;
    assign icache_m_axi_rresp = m_axi_rresp;
    assign dcache_m_axi_rresp = m_axi_rresp;
    assign icache_m_axi_rlast = m_axi_rlast;
    assign dcache_m_axi_rlast = m_axi_rlast;
    assign icache_m_axi_rvalid = m_axi_rid[0] ? 1'b0 : m_axi_rvalid;
    assign dcache_m_axi_rvalid = m_axi_rid[0] ? m_axi_rvalid : 1'b0;
    assign m_axi_rready = m_axi_rid[0] ? dcache_m_axi_rready : icache_m_axi_rready;

endmodule
