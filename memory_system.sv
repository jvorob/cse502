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
    
    //=== Special inputs
    input  logic [1:0]  curr_priv_mode, //M/S/U //TODO
    input  logic [63:0] csr_SATP,   //current value of SATP CSR
    input  logic        csr_SUM,    //TODO: determines if S mode can load/store U-mode virtual pages

    //=== External I$ interface
    input  logic        ic_en,
    input  logic [63:0] ic_req_addr,

    output logic        ic_resp_valid,     // when resp_valid, it's either a page fault or a valid inst
    output logic        ic_resp_page_fault, // if page_fault == 1, ignore resp_inst
    output logic [31:0] ic_resp_inst,

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


    // ====================================
    //
    //          SATP Mode Handling
    //
    // ====================================

    // === SATP decode
    logic [3:0] satp_mode;
    logic [15:0] satp_asid; //TODO: check ASID
    logic [43:0] satp_ppn;
    assign {satp_mode, satp_asid, satp_ppn} = csr_SATP;

    logic virtual_en;
    logic [63:0] root_pt_addr;

    // === Decode mode into virtual/physical/error
    always_comb begin
        virtual_en = 0;

        // SATP csr only applies in S and U modes
        if (curr_priv_mode != PRIV_M) begin
            case (satp_mode) inside
                0: ; //physical mode
                8: $error("SATP set to mode 8, 'Sv39', not supported");
                9: virtual_en = 1; //Sv48
                default: $error("SATP set to unsupported mode %d\n", satp_mode);
            endcase
        end
    end

    // === get pt address
    // (ppn is actuall 44 bits, so top 2 bits get ignored, but that 
    //  seems to be the intent of the spec)
    assign root_pt_addr = { satp_ppn, 12'b0 };


    // ====================================
    //
    //          Main memory wiring
    //
    // ====================================

    /*  ============= Structure overview:
     *  --- Interface to pipeline:
     *   I$_in, I$_out ports
     *   D$_in, D$_out ports
     *
     *  --- Interface to pipeline:
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
    
    // I$ permissions checking
    always_comb begin
        ic_resp_page_fault = 0;

        // If we're in virtual mode and succesfully found a mapping, check the perms
        if ( virtual_en && itlb.pa_valid ) begin
            if ( itlb.pte_perm[0] == 0) begin // V: must be valid
                ic_resp_page_fault = 1;

            end else if ( itlb.pte_perm[3] == 0) begin // X: must be executable
                ic_resp_page_fault = 1;

            end else if ( itlb.pte_perm[4] == 0 && curr_priv_mode == PRIV_U) begin // U: 
                ic_resp_page_fault = 1; //!U pages can't be execced by user

            end else if ( itlb.pte_perm[4] == 1 && curr_priv_mode != PRIV_U) begin // U:
                ic_resp_page_fault = 1; //U pages can't by execced by S

            end else if ( itlb.pte_perm[6] == 0) begin // A: fault so software can set accessed bit
                ic_resp_page_fault = 1;
            end
        end
    end


    // Give output to user if we get a response from I$ or if TLB identifies a page fault
    // on page fault, zero out resulting instruction for ease of debugging
    assign ic_resp_valid = icache.icache_valid || ic_resp_page_fault;
    assign ic_resp_inst = ic_resp_page_fault ? 0 : icache.out_inst; 
    
    // If we encounter a page fault, I$ will sit and wait
    Icache icache (
            .clk, 
            .reset,
        
            .in_fetch_addr  (ic_req_addr),  //In
            .icache_enable  (ic_en),
            .out_inst       (), //Out
            .icache_valid   (),

            .virtual_mode   (virtual_en),           // virtual-mode enable
            .translated_addr       (itlb.pa),       //translation from I-TLB
            .translated_addr_valid (itlb.pa_valid && !ic_resp_page_fault), 

            .*  //this links all the icache_m_axi ports
    );



    // =================== TLBs
    //only need to query the tlbs if virt mode is enabled and $ is being accessed
    logic dtlb_req_valid; 
    logic itlb_req_valid;
    assign dtlb_req_valid = virtual_en && dc_en;
    assign itlb_req_valid = virtual_en && ic_en;

    
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
       .pte_perm(),
        

       // MMU Connection
       .req_addr(),                          //Out to MMU
       .req_valid(),  //set on TLB miss
       .resp_addr     (mmu.resp_data_addr),  //In from MMU
       .resp_perm_bits(mmu.resp_data_perms),
       .resp_valid    (mmu.resp1_valid)
    );



    // =================== MMU
    // TLBs request translations from MMU on miss
    
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
        .root_pt_addr(root_pt_addr) // Currently set by havetlb hack, later will be from csr
    );
    


    // this grabs all the m_axi, icache_m_axi, and dcache_m_axi ports
    // and wires them together
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
