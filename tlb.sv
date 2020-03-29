`ifndef TLB
`define TLB

`include "MMU.sv" //for definition of 'tlb_perm_bits'

// This file holds the D-TLB and I-TLB

module Dtlb
#(
    VPN_BITS = 36,              // Actually only 36 bits for Sv48 but the MMU will expect/respond with 64 bits
    PPN_BITS = 44,              // Actually only 44 bits for Sv48
    EXTENDED_VPN = 64,
    EXTENDED_PPN = 64,
    OFFSET_BITS = 12
)
(
    input clk,
    input reset,

    // The virtual address to be translated
    input va_valid,
    input [EXTENDED_VPN-1:0] va,

    // The physical address that results from translation and the
    // corresponding PTE's permission bits
    output pa_valid,
    output [EXTENDED_PPN-1:0] pa,
    output tlb_perm_bits pte_perm,

    // Communication with MMU
    output [EXTENDED_VPN-1:0] req_addr,
    output req_valid,

    input [EXTENDED_PPN-1:0] resp_addr,
    input tlb_perm_bits resp_perm_bits,
    input resp_valid
);
//    localparam SIZE = 16 * 1024; // size of cache in bytes
    localparam WAYS = 1;
    localparam SETS = 512;
    localparam LOG_SETS = 9;
    
    localparam VPN_UPPER = VPN_BITS + OFFSET_BITS - 1;
    localparam VPN_LOWER = OFFSET_BITS;
    localparam PPN_UPPER = PPN_BITS + OFFSET_BITS - 1;
    localparam PPN_LOWER = OFFSET_BITS;
    
    logic valid_entry [SETS][WAYS];             // If TLB entry is valid
    logic [VPN_BITS-1:0] tlb_vas [SETS][WAYS];  // TLB virtual addresses
    logic [PPN_BITS-1:0] tlb_pas [SETS][WAYS]; // TLB physical addresses
    tlb_perm_bits perms [SETS][WAYS];           // page permissions

    logic [EXTENDED_VPN-1:0] requested_va;

    logic [EXTENDED_VPN-1:0] rplc_va;
    logic [EXTENDED_PPN-1:0] rplc_pa;
    logic [LOG_SETS-1:0] rplc_index;
    tlb_perm_bits rplc_perm;
    
    logic [LOG_SETS-1:0] index;

    assign rplc_va = requested_va;
    assign rplc_index = rplc_va[LOG_SETS-1+VPN_LOWER:VPN_LOWER];
    assign rplc_perm = resp_perm_bits;

    assign index = va[LOG_SETS-1+VPN_LOWER:VPN_LOWER];


    logic [1:0] state;

    assign pa = { {EXTENDED_PPN-OFFSET_BITS-PPN_BITS{1'b0}}, tlb_pas[index][0], {OFFSET_BITS{1'b0}} };
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

            requested_va <= 0;
        end
        else if (state == 0) begin
            // wait for request
            pa_valid <= 0;
            if (va_valid) begin
                if (tlb_vas[index][0] == va[VPN_UPPER:VPN_LOWER] && valid_entry[index][0] == 1) begin
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
            requested_va <= va;
            req_addr <= va;
            req_valid <= 1;
            state <= 2;
        end
       else if (state == 2) begin
            if (resp_valid) begin
               tlb_vas[rplc_index][0] <= requested_va[VPN_UPPER:VPN_LOWER];
               tlb_pas[rplc_index][0] <= resp_addr[PPN_UPPER:PPN_LOWER];
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
    VPN_BITS = 36,              // Actually only 36 bits for Sv48 but the MMU will expect/respond with 64 bits
    PPN_BITS = 44,              // Actually only 44 bits for Sv48
    EXTENDED_VPN = 64,
    EXTENDED_PPN = 64,
    OFFSET_BITS = 12
)
(
    input clk,
    input reset,

    // The virtual address to be translated
    input va_valid,
    input [EXTENDED_VPN-1:0] va,

    // The physical address that results from translation and the
    // corresponding PTE's permission bits
    output pa_valid,
    output [EXTENDED_PPN-1:0] pa,
    output tlb_perm_bits pte_perm,

    // Communication with MMU
    output [EXTENDED_VPN-1:0] req_addr,
    output req_valid,

    input [EXTENDED_PPN-1:0] resp_addr,
    input tlb_perm_bits resp_perm_bits,
    input resp_valid
);
    // I-TLB is currently the exact same as the D-TLB
    Dtlb hidden_dtlb (.*);

endmodule

`endif
