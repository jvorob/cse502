`include "dcache.sv"
`include "icache.sv"
`include "axi_interconnect.sv"

// Wrapper module for all memory-interacting components
// (caches, TLBs, MMU)
// all accesses to caches should be done through this module
module MemorySystem
#(
  ID_WIDTH = 13,
  ADDR_WIDTH = 64,
  DATA_WIDTH = 64,
  STRB_WIDTH = DATA_WIDTH/8
)
(
    input clk,
    input reset,

    // 1 = enable virtual memory/TLB use
    // applies to both D$ and I$
    input  logic        virtual_en, 

    //=== External I$ interface
    input  logic [63:0] ic_req_addr,
    output logic [31:0] ic_resp_inst,
    output logic        ic_resp_valid,

    //=== External D$ interface
    input  logic        dc_en,
    input  logic [63:0] dc_in_addr,

    input  logic        dc_write_en, // write=1, read=0
    input  logic [63:0] dc_in_wdata,
    input  logic [ 1:0] dc_in_wlen,  // wlen is log(#bytes), 3 = 64bit write

    output logic [63:0] dc_out_rdata,
    output logic        dc_out_rvalid,     //TODO: we should maybe merge rvalid and write_done
    output logic        dc_out_write_done,


    //==== Main AXI interface
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
    output  wire [ID_WIDTH-1:0]    m_axi_arid,
    output  wire [ADDR_WIDTH-1:0]  m_axi_araddr,
    output  wire [7:0]             m_axi_arlen,
    output  wire [2:0]             m_axi_arsize,
    output  wire [1:0]             m_axi_arburst,
    output  wire                   m_axi_arlock,
    output  wire [3:0]             m_axi_arcache,
    output  wire [2:0]             m_axi_arprot,
    output  wire                   m_axi_arvalid,
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


    Icache icache (
            .clk, 
            .reset,

            .fetch_addr  (ic_req_addr),
            .out_inst    (ic_resp_inst),
            .icache_valid(ic_resp_valid),

            .*  //this links all the icache_m_axi ports
    );

    Dcache dcache (
        .clk, 
        .reset,

        .virtual_mode(virtual_en), // virtual-mode enable

        .dcache_enable(dc_en),
        .in_addr(dc_in_addr),

        .wrn  (dc_write_en),
        .wdata(dc_in_wdata),
        .wlen (dc_in_wlen),

        .rdata       (dc_out_rdata),
        .dcache_valid(dc_out_rvalid),
        .write_done  (dc_out_write_done),

        .trns_tag(0),           //translation from tlb (TODO)
        .trns_tag_valid(1'b0),  //translation_valid    (TODO)

        .* //this links all the dcache_m_axi ports
    );

    


    // this grabs all the m_axi, icache_m_axi, and dcache_m_axi ports
    // and wire them together
    AXI_interconnect axi_interconnect (.*);

    // === ICACHE-AXI port
 
    wire [ID_WIDTH-1:0]     icache_m_axi_arid;
    wire [ADDR_WIDTH-1:0]   icache_m_axi_araddr;
    wire [7:0]              icache_m_axi_arlen;
    wire [2:0]              icache_m_axi_arsize;
    wire [1:0]              icache_m_axi_arburst;
    wire                    icache_m_axi_arlock;
    wire [3:0]              icache_m_axi_arcache;
    wire [2:0]              icache_m_axi_arprot;
    wire                    icache_m_axi_arvalid;
    wire                    icache_m_axi_arready;
    wire [ID_WIDTH-1:0]     icache_m_axi_rid;
    wire [DATA_WIDTH-1:0]   icache_m_axi_rdata;
    wire [1:0]              icache_m_axi_rresp;
    wire                    icache_m_axi_rlast;
    wire                    icache_m_axi_rvalid;
    wire                    icache_m_axi_rready;
    wire                    icache_m_axi_acvalid;
    wire                    icache_m_axi_acready;
    wire [ADDR_WIDTH-1:0]   icache_m_axi_acaddr;
    wire [3:0]              icache_m_axi_acsnoop;

    // === DCACHE-AXI port
    wire [ID_WIDTH-1:0]     dcache_m_axi_awid;
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr;
    wire [7:0]              dcache_m_axi_awlen;
    wire [2:0]              dcache_m_axi_awsize;
    wire [1:0]              dcache_m_axi_awburst;
    wire                    dcache_m_axi_awlock;
    wire [3:0]              dcache_m_axi_awcache;
    wire [2:0]              dcache_m_axi_awprot;
    wire                    dcache_m_axi_awvalid;
    wire                    dcache_m_axi_awready;
    wire [DATA_WIDTH-1:0]   dcache_m_axi_wdata;
    wire [STRB_WIDTH-1:0]   dcache_m_axi_wstrb;
    wire                    dcache_m_axi_wlast;
    wire                    dcache_m_axi_wvalid;
    wire                    dcache_m_axi_wready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_bid;
    wire [1:0]              dcache_m_axi_bresp;
    wire                    dcache_m_axi_bvalid;
    wire                    dcache_m_axi_bready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_arid;
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_araddr;
    wire [7:0]              dcache_m_axi_arlen;
    wire [2:0]              dcache_m_axi_arsize;
    wire [1:0]              dcache_m_axi_arburst;
    wire                    dcache_m_axi_arlock;
    wire [3:0]              dcache_m_axi_arcache;
    wire [2:0]              dcache_m_axi_arprot;
    wire                    dcache_m_axi_arvalid;
    wire                    dcache_m_axi_arready;
    wire [ID_WIDTH-1:0]     dcache_m_axi_rid;
    wire [DATA_WIDTH-1:0]   dcache_m_axi_rdata;
    wire [1:0]              dcache_m_axi_rresp;
    wire                    dcache_m_axi_rlast;
    wire                    dcache_m_axi_rvalid;
    wire                    dcache_m_axi_rready;
    wire                    dcache_m_axi_acvalid;
    wire                    dcache_m_axi_acready;
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_acaddr;
    wire [3:0]              dcache_m_axi_acsnoop;

endmodule
