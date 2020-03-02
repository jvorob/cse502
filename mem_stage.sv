
module mem_stage
#(
    ID_WIDTH = 13,
    ADDR_WIDTH = 64,
    DATA_WIDTH = 64,
    STRB_WIDTH = DATA_WIDTH/8
)
(
    input clk,
    input reset,

    input decoded_inst_t inst,
    input [63:0] ex_data,
    input [63:0] ex_data2,
    input is_bubble,

    output logic dcache_en,
    output [63:0] mem_ex_rdata,

    // AXI signals
    wire [ID_WIDTH-1:0]     dcache_m_axi_awid,
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_awaddr,
    wire [7:0]              dcache_m_axi_awlen,
    wire [2:0]              dcache_m_axi_awsize,
    wire [1:0]              dcache_m_axi_awburst,
    wire                    dcache_m_axi_awlock,
    wire [3:0]              dcache_m_axi_awcache,
    wire [2:0]              dcache_m_axi_awprot,
    wire                    dcache_m_axi_awvalid,
    wire                    dcache_m_axi_awready,
    wire [DATA_WIDTH-1:0]   dcache_m_axi_wdata,
    wire [STRB_WIDTH-1:0]   dcache_m_axi_wstrb,
    wire                    dcache_m_axi_wlast,
    wire                    dcache_m_axi_wvalid,
    wire                    dcache_m_axi_wready,
    wire [ID_WIDTH-1:0]     dcache_m_axi_bid,
    wire [1:0]              dcache_m_axi_bresp,
    wire                    dcache_m_axi_bvalid,
    wire                    dcache_m_axi_bready,
    wire [ID_WIDTH-1:0]     dcache_m_axi_arid,
    wire [ADDR_WIDTH-1:0]   dcache_m_axi_araddr,
    wire [7:0]              dcache_m_axi_arlen,
    wire [2:0]              dcache_m_axi_arsize,
    wire [1:0]              dcache_m_axi_arburst,
    wire                    dcache_m_axi_arlock,
    wire [3:0]              dcache_m_axi_arcache,
    wire [2:0]              dcache_m_axi_arprot,
    wire                    dcache_m_axi_arvalid,
    wire                    dcache_m_axi_arready,
    wire [ID_WIDTH-1:0]     dcache_m_axi_rid,
    wire [DATA_WIDTH-1:0]   dcache_m_axi_rdata,
    wire [1:0]              dcache_m_axi_rresp,
    wire                    dcache_m_axi_rlast,
    wire                    dcache_m_axi_rvalid,
    wire                    dcache_m_axi_rready
);
    logic dcache_valid; 
    logic write_done;
    logic [63:0] mem_rdata;
    logic [63:0] mem_wr_data; // Write data

    assign dcache_en = (inst.is_load || inst.is_store) && !is_bubble;

    always_comb begin
        // This case only matters for stores
        case (inst.funct3)
            F3LS_B: mem_wr_data = ex_data2[7:0];
            F3LS_H: mem_wr_data = ex_data2[15:0];
            F3LS_W: mem_wr_data = ex_data2[31:0];
            F3LS_D: mem_wr_data = ex_data2[63:0];
            default: mem_wr_data = ex_data2[63:0];
        endcase

        // This only matters for loads
        case (inst.funct3)
            // load signed
            F3LS_B: mem_ex_rdata = { {56{mem_rdata[7]}}, mem_rdata[7:0] };
            F3LS_H: mem_ex_rdata = { {48{mem_rdata[15]}}, mem_rdata[15:0] };
            F3LS_W: mem_ex_rdata = { {32{mem_rdata[31]}}, mem_rdata[31:0] };
            // load unsigned
            F3LS_BU: mem_ex_rdata = { 56'd0, mem_rdata[7:0] };
            F3LS_HU: mem_ex_rdata = { 48'd0, mem_rdata[15:0] };
            F3LS_WU: mem_ex_rdata = { 32'd0, mem_rdata[31:0] };
            default: mem_ex_rdata = mem_rdata;
        endcase
    end

    Dcache dcache (
        .addr(ex_data),
        .wdata(mem_wr_data),
        .wlen(inst.funct3[1:0]),
        .dcache_enable(dcache_en),
        .wrn(inst.is_store),
        .rdata(mem_rdata),
        .dcache_valid(dcache_valid),
        .write_done(write_done),
        .*
    );
endmodule

