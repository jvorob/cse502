`ifndef TLB
`define TLB

`include "MMU.sv" //for definition of 'tlb_perm_bits'

// This file holds the D-TLB and I-TLB

module Dtlb
#(
    VPN_BITS = 64,              // Actually only 36 bits for Sv48 but the MMU will expect/respond with 64 bits
//    PPN_BITS = 44,              // Actually only 44 bits for Sv48
    EXTENDED_PPN = 52           // PPN is only 44 bits but we 0 extend it to 52 (+12 bit offset gives 64 bits)
)
(
    input clk,
    input reset,

    // The virtual address to be translated
    input va_valid,
    input [VPN_BITS-1:0] va,

    // The physical address that results from translation and the
    // corresponding PTE's permission bits
    output pa_valid,
    output [EXTENDED_PPN-1:0] pa,
    output tlb_perm_bits pte_perm,

    // Communication with MMU
    output [VPN_BITS-1:0] req_addr,
    output req_valid,

    input [EXTENDED_PPN-1:0] resp_addr,
    input tlb_perm_bits resp_perm_bits,
    input resp_valid
);
    localparam PTE_LEN = 8; // size of PTE in bytes
    localparam LOG_PTE_LEN = 3; // log(size of PTE)

//    localparam SIZE = 16 * 1024; // size of cache in bytes
    localparam WAYS = 1;
    localparam SETS = 512;
    localparam LOG_SETS = 9;
    
    logic valid_entry [SETS][WAYS];             // If TLB entry is valid
    logic [VPN_BITS-1:0] tlb_vas [SETS][WAYS];  // TLB virtual addresses
    logic [EXTENDED_PPN-1:0] tlb_pas [SETS][WAYS]; // TLB physical addresses
    tlb_perm_bits perms [SETS][WAYS];           // page permissions
   
    logic [VPN_BITS-1:0] rplc_va = va;
    logic [EXTENDED_PPN-1:0] rplc_pa = resp_addr;
    tlb_perm_bits rplc_perm = resp_perm_bits;
    logic [LOG_SETS-1:0] rplc_index = va[LOG_SETS-1:0];

//    logic [VPN_BITS-LOG_SETS-1:0] tag = va[VPN_BITS-1:LOG_SETS];
    logic [LOG_SETS-1:0] index = va[LOG_SETS-1:0];
//    logic rplc_way;

    logic [1:0] state;

    assign pa = tlb_pas[index][0]; //TODO: these seem like a bug?
    assign pte_perm = perms[index][0];

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_entry <= '{default:0};
            tlb_vas <= '{default:0};
            tlb_pas <= '{default:0};
            perms <= '{default:0};
            
            state <= 0;

            pa_valid <= 0;

            req_addr <= 0;
            req_valid <= 0;
        end
        else if (state == 0) begin
            // wait for request
            pa_valid <= 0;
            if (va_valid) begin
                if (tlb_vas[index][0] == va && valid_entry[index][0] == 1) begin
                    // found translation. output it.
                    state <= 3;
                    pa_valid <= 1;
                end
                else begin
                    // translation not found or not valid.
                    state <= 1;
                end
            end
        end
        else if (state == 1) begin
            // retrieve the translation from mmu
            req_addr <= va;
            req_valid <= 1;
            state <= 2;
        end
        else if (state == 2) begin
            if (resp_valid) begin
               tlb_vas[rplc_index][0] <= va;
               tlb_pas[rplc_index][0] <= resp_addr;
               perms[rplc_index][0] <= resp_perm_bits;
               valid_entry[rplc_index][0] <= 1;
               req_valid <= 0;
               state <= 0;
            end
        end
        else if (state == 3) begin
            // This state is just meant to give the pipeline a cycle to deassert va_valid (the valid request signal) to this module.
            // Otherwise this module would return to cycle 0 and begin output a 2nd cycle for the same request.
            pa_valid <= 0;
            state <= 0;
        end
    end
endmodule

module Itlb
#(
    VPN_BITS = 64,              // Actually only 36 bits for Sv48 but the MMU will expect/respond with 64 bits
//    PPN_BITS = 44,              // Actually only 44 bits for Sv48
    EXTENDED_PPN = 52           // PPN is only 44 bits but we 0 extend it to 52 (+12 bit offset gives 64 bits)
)
(
    input clk,
    input reset,

    // The virtual address to be translated
    input va_valid,
    input [VPN_BITS-1:0] va,

    // The physical address that results from translation and the
    // corresponding PTE's permission bits
    output pa_valid,
    output [EXTENDED_PPN-1:0] pa,
    output tlb_perm_bits pte_perm,

    // Communication with MMU
    output [VPN_BITS-1:0] req_addr,
    output req_valid,

    input [EXTENDED_PPN-1:0] resp_addr,
    input tlb_perm_bits resp_perm_bits,
    input resp_valid
);
    // I-TLB is currently the exact same as the D-TLB
    Dtlb hidden_dtlb (.*);

endmodule

`endif
