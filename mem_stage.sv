
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

    output dcache_valid,
    output write_done,
    output logic dcache_en,
    output [63:0] mem_ex_rdata,

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
    output  wire                    dcache_m_axi_rready,
    input   wire                    dcache_m_axi_acvalid,
    output  wire                    dcache_m_axi_acready,
    input   wire [ADDR_WIDTH-1:0]   dcache_m_axi_acaddr,
    input   wire [3:0]              dcache_m_axi_acsnoop
);
    logic [63:0] mem_rdata;
    logic [63:0] mem_wr_data; // Write data

    assign dcache_en = (inst.is_load || inst.is_store) && !is_bubble;

    logic [5:0] shift_amt;
    assign shift_amt = {ex_data[2:0], 3'b000};
    logic [63:0] mem_rdata_shifted;

    always_comb begin
        // This case only matters for stores
        case (inst.funct3)
            F3LS_B: mem_wr_data = ex_data2[7:0];
            F3LS_H: mem_wr_data = ex_data2[15:0];
            F3LS_W: mem_wr_data = ex_data2[31:0];
            F3LS_D: mem_wr_data = ex_data2[63:0];
            default: mem_wr_data = ex_data2[63:0];
        endcase

        mem_rdata_shifted = mem_rdata >> shift_amt;
        
        // This only matters for loads
        case (inst.funct3)
            // load signed
            F3LS_B: mem_ex_rdata = { {56{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0] };
            F3LS_H: mem_ex_rdata = { {48{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0] };
            F3LS_W: mem_ex_rdata = { {32{mem_rdata_shifted[31]}}, mem_rdata_shifted[31:0] };
            // load unsigned
            F3LS_BU: mem_ex_rdata = { 56'd0, mem_rdata_shifted[7:0] };
            F3LS_HU: mem_ex_rdata = { 48'd0, mem_rdata_shifted[15:0] };
            F3LS_WU: mem_ex_rdata = { 32'd0, mem_rdata_shifted[31:0] };
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

