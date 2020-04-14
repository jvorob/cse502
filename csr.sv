
// Currently, traps and exceptions aren't supported in our processor,
// so we won't do anything when CSRs are accessed inappropriately.
module Control_Status_Reg
#(
    REG_WIDTH = 64,
    CSR_COUNT = 4096,
    CSR = 12  // Num CSR bits
)
(
    input clk,
    input reset,

    // target address of instruction
    input [CSR-1:0] addr,
    input [REG_WIDTH-1:0] val,  // rs1 or zimm based on instruction

    input valid,        // Valid instruction (not bubble)
    input is_csr,
    input csr_rw,       // Read write
    input csr_rs,       // Read set
    input csr_rc,       // Read clear
    
    output [REG_WIDTH-1:0] csr_result, // The value to be written to rd.

    output [REG_WIDTH-1:0] mepc_csr,
    output [REG_WIDTH-1:0] satp_csr
);
    logic [REG_WIDTH-1:0] csrs [0:CSR_COUNT-1]; // The CSR registers

    logic [1:0] csr_rw_perm;
    logic [1:0] lowest_priv;

    assign csr_rw_perm = addr[CSR-1:CSR-2];
    assign lowest_priv = addr[CSR-3:CSR-4];

    assign csr_result = csrs[addr]; // Combinationally read CSRs
    assign mepc_csr = csrs[mepc];
    assign satp_csr = csrs[satp];

    always_ff @(posedge clk) begin
        if (reset) begin
            csrs <= '{default:0};
//            integer i;
//            for (i = 0; i < CSR_COUNT; i = i + 1) begin
//                csrs[i] <= 64'h0;
//            end
        end
        else if (valid && is_csr) begin
            if (csr_rw) begin
                csrs[addr] <= val;
            end
            else if (csr_rs) begin
                csrs[addr] <= csrs[addr] | val;
            end
            else begin // This is the condition for csr_rc.
                csrs[addr] <= csrs[addr] & (~val);
            end
        end
    end

    logic [REG_WIDTH-1:0] mepc_debug;
    logic [REG_WIDTH-1:0] satp_debug;
/*
    logic [REG_WIDTH-1:0] ;
    logic [REG_WIDTH-1:0] ;
    logic [REG_WIDTH-1:0] ;
    logic [REG_WIDTH-1:0] ;
    logic [REG_WIDTH-1:0] ;
    logic [REG_WIDTH-1:0] ;
*/
    assign mepc_debug = csrs[mepc];
    assign satp_debug = csrs[satp];


endmodule

