`include "dcache.sv"
`include "icache.sv"
`include "axi_interconnect.sv"
`include "MMU.sv"
`include "tlb.sv"

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
    
    input  logic        virtual_en, // 1 = enable virtual memory/TLB use (both for I/D cache)
    input  logic [63:0] satp, //current value of SATP CSR (TODO TEMP: with havetlb hack, this is just an address)

    //=== External I$ interface
    input  logic        ic_en,   //TODO: this is unused right now?
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


    /* Structure overview:
     *   I$_in ports
     *   D$_in ports
     *
     *   I$_in -> I$.port
     *   if virtual: 
     *      I$_in -> ITLB, ITLB -> I$.translated
     *
     *
     *   D$_in -> D_MUX
     *   MMU ->   D_MUX
     *   if MMU_ovveride:
     *      MMU-----mux--->D$
     *   else:
     *      D$_in---mux--->D$
     *
     *   if virtual:
     *      D$_in -> DTLB, DTLB->D$.translated
     */


    // Extra, muxed signals for D$
    logic        dcmux_en;
    logic [63:0] dcmux_in_addr;
    logic        dcmux_write_en; // write=1, read=0
    logic [63:0] dcmux_in_wdata;
    logic [ 1:0] dcmux_in_wlen;  // wlen is log(#bytes), 3 = 64bit write

    // === D$ input mux: switches D$ between serving outside request or serving MMU
    // When mmu is using D$, input is always a read
    assign dcmux_in_addr         = mmu.use_dcache ? mmu.dcache_req_addr : dc_in_addr;
    assign dcmux_en              = mmu.use_dcache ? 1                   : dc_en;

    assign dcmux_write_en        = mmu.use_dcache ? 0 : dc_write_en; 
    assign dcmux_in_wdata        = mmu.use_dcache ? 0 : dc_in_wdata;
    assign dcmux_in_wlen         = mmu.use_dcache ? 0 : dc_in_wlen;

    // When mmu is using D$, disable all output
    assign dc_out_rdata       = mmu.use_dcache ? 0 : dcache.rdata;
    assign dc_out_rvalid      = mmu.use_dcache ? 0 : dcache.dcache_valid;
    assign dc_out_write_done  = mmu.use_dcache ? 0 : dcache.write_done; 



    // Switch DCache to physical mode when MMU is using it
    logic dcmux_virtual_en;
    assign dcmux_virtual_en = virtual_en && !mmu.use_dcache;

    Dcache dcache (
        .clk, 
        .reset,
        .virtual_mode(dcmux_virtual_en), // virtual-mode enable

        .dcache_enable(dcmux_en),
        .in_addr(dcmux_in_addr),

        .wrn  (dcmux_write_en),
        .wdata(dcmux_in_wdata),
        .wlen (dcmux_in_wlen),

        .rdata       (),
        .dcache_valid(),
        .write_done  (),

        .translated_addr      (dtlb.pa),      // translation from D-TLB
        .translated_addr_valid(dtlb.pa_valid),

        .* //this links all the dcache_m_axi ports
    );



    // =================== Icache is fairly straightforward
    Icache icache (
            .clk, 
            .reset,
        
            .virtual_mode   (virtual_en), // virtual-mode enable

            .in_fetch_addr  (ic_req_addr),
            .out_inst       (ic_resp_inst),
            .icache_valid   (ic_resp_valid),

            .translated_addr       (itlb.pa),       //translation from I-TLB
            .translated_addr_valid (itlb.pa_valid), 

            .*  //this links all the icache_m_axi ports
    );



    // =================== TLBs
    //only need to query the tlbs if virt mode is enabled and $ is being accessed
    logic dtlb_req_valid; 
    logic itlb_req_valid;
    assign dtlb_req_valid = virtual_en && dc_en;
    assign itlb_req_valid = virtual_en; // TODO: once we have I$_en, add that in

    
    Dtlb dtlb(
       .clk,
       .reset,
       
       .va_valid(dtlb_req_valid), //Input
       .va      (dc_in_addr),
       .pa_valid(),               //Out to D$
       .pa(),
       .pte_perm(/* TODO: make use of this once we start checking permissions */),

        // MMU connection
       .req_addr (),                             //Out to mmu
       .req_valid(), // set on TLB miss
       .resp_addr     (mmu.resp_data_addr),      //In from mmu
       .resp_perm_bits(mmu.resp_data_perms),
       .resp_valid    (mmu.resp0_valid)   //DTLB is on port0
    );

    Itlb itlb(
       .clk,
       .reset,
       
       .va_valid(itlb_req_valid), // Input
       .va      (ic_req_addr),
       .pa_valid(),               // Out to D$
       .pa(),
       .pte_perm(/*TODO*/),
        

       // MMU Connection
       .req_addr(),                          //Out to MMU
       .req_valid(),  //set on TLB miss
       .resp_addr     (mmu.resp_data_addr),  //In from MMU
       .resp_perm_bits(mmu.resp_data_perms),
       .resp_valid    (mmu.resp1_valid)
    );



    // =================== MMU

    //TODO: once we have a tlb, the tlbs will pass on misses to MMU
    //for now, just send all TLB directly requests to MMU
    MMU mmu (
        .clk,
        .reset,

        // ====== Two input ports (from I/D TLB)
        .req0_addr (dtlb.req_addr),      //port0 is for D-TLB (takes priority)
        .req0_valid(dtlb.req_valid),
        .req1_addr (itlb.req_addr),      //port1 is for I-TLB
        .req1_valid(itlb.req_valid),

        // ====== Response (to I/D TLB)
        .resp_data_addr(),  
        .resp_data_perms(), 
        .resp0_valid(), // if data is for port 0
        .resp1_valid(), // if data is for port 1

        // ====== D-Cache interface (used to access memory)
        .use_dcache(), // outputs
        .dcache_req_addr(),
        .dcache_resp_valid(dcache.dcache_valid), //inputs
        .dcache_resp_data (dcache.rdata),

        // ====== MISC
        .root_pt_addr(satp) // Currently set by havetlb hack, later will be from csr
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
