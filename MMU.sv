

typedef struct packed {
    logic TODO;
    //fill this in with the actual bits (resident, rwx?, superuser vs user?)

} tlb_perm_bits;


// AXI Enums
typedef enum bit[1:0] {
	MMU_IDLE		= 2'b00,
	MMU_FETCHING	= 2'b01, // there'll be a counter for this
	MMU_DONE		= 2'b10,
	MMU_RESERVED	= 2'b11
} MMU_State; // ARBURST or AWBURST


module MMU 
#( // Constant params

)
( // IO
    input clk,
    input reset,

    // ====== Two input ports (from I/D TLB)
    input  logic [63:0]          req0_addr,
    input  logic                 req0_valid,

    input  logic [63:0]          req1_addr,
    input  logic                 req1_valid,

    // ====== Response (to I/D TLB)
    output logic [63:0]          resp_data_addr,  // the translated address
    output tlb_perm_bits         resp_data_perms, // that pages' permission bits

    // output logic                 mmu_busy, //might be useful to have? we only latch in a req once

    // response valid signals
    output logic                 resp0_valid, // if data is for port 0
    output logic                 resp1_valid, // if data is for port 1



    // ====== D-Cache interface (used to access memory)
    output logic                 use_dcache, // takes over control of D$ and forces physical-mode
    output logic [63:0]          dcache_req_addr,

    input  logic                 dcache_resp_valid, //response from D$
    input  logic [63:0]          dcache_resp_data,


    // ====== MISC
    input  logic [63:0]          root_pt_addr // Currently set by havetlb hack, later will be from csr
);
    localparam LEVELS = 4; //defalt for sv48

    MMU_State state;

    // == Set once per request
    logic curr_port; //0 is serving port1, 1 is serving port2
    logic [63:0] translate_addr;  //this is the address we're trying to translate

    logic [63:0] final_pte; // this will hold the leaf_pte when we're done walking the tree

    // == Updated at each level of the tree
    logic [3:0]  curr_level;    //LEVELS-1 for root, 0 for last level
    logic [63:0] curr_pt_addr; // points to current level of PT in walk


    // === Aliases / intermediate signals
    
    logic [11:0]     translate_addr_offset;
    logic [3:0][8:0] translate_addr_vpn;
    assign translate_addr_offset = translate_addr[11: 0];
    assign translate_addr_vpn[0] = translate_addr[20:12];
    assign translate_addr_vpn[1] = translate_addr[29:21];
    assign translate_addr_vpn[2] = translate_addr[38:30];
    assign translate_addr_vpn[3] = translate_addr[47:39];

    logic [8:0] curr_vpn;
    assign curr_vpn = translate_addr_vpn[curr_level];

    // Valid for current value of dcache_resp_data
    logic     dcache_resp_x, dcache_resp_w, dcache_resp_r, dcache_resp_v;
    assign  { dcache_resp_x, dcache_resp_w, dcache_resp_r, dcache_resp_v } = dcache_resp_data[3:0];

    // == Dcache fetch signals: if fetching, request correct PTE in current page table
    always_comb begin
        // defaults:
        use_dcache = 0;
        dcache_req_addr = 0;

        if (state == MMU_FETCHING) begin
            //current_pt_addr,                  bottom 12-bit offset is vpn*8
            dcache_req_addr = { curr_pt_addr[63:12],  curr_vpn[8:0], 3'b000};
            use_dcache = 1;
        end
    end


    // == Response logic: parses out from leaf_pte
    always_comb begin
        // defaults:
        resp_data_addr = 0;
        resp_data_perms = 0;
        resp0_valid = 0;
        resp1_valid = 0;

        //TODO: also handle selecting between ports 0 and 1
        if (state == MMU_DONE) begin
            resp0_valid = 1;
            resp_data_perms = 0; //TODO
            resp_data_addr = leafToTranslatedAddress(final_pte, translate_addr_vpn, curr_level);
        end
    end



    // === State Transitions

    always_ff @(posedge clk) begin
        if (reset) begin
            curr_level <= 0;
            curr_port <= 0;
            state <= MMU_IDLE;
            translate_addr <= 0;
        end else begin

            case (state) inside
                MMU_IDLE: begin
                    //stay idle until we get a request
                    
                    if (req0_valid || req1_valid) begin 
                        state <= MMU_FETCHING;

                        //req 0 takes priority over 1
                        translate_addr <= req0_valid ? req0_addr : req1_addr;
                        curr_port <= req0_valid ? 0 : 1;

                        // == Initialize fetch to root of page table
                        curr_level <= LEVELS-1;
                        curr_pt_addr <= root_pt_addr;

                    end
                end

                MMU_FETCHING: begin
                    // wait until we get some data back
                    if (dcache_resp_valid) begin

                        // === Error checking
                        if (!dcache_resp_v && curr_level != 3) //check pte valid bit (TEMP: skip this for root)
                            $error("Error, invalid PTE at %x", curr_pt_addr);
                        if (dcache_resp_w && !dcache_resp_r)
                            $error("Error, PTE has write && !read at %x", curr_pt_addr);



                        // === If pointer: follow it
                        if (!dcache_resp_r && !dcache_resp_w && !dcache_resp_x) begin
                            if (curr_level == 0)
                                $error("Error: fell off page table at %x", curr_pt_addr);

                            // physical address is bits 53:8 of PTE, with a 12-bit offset
                            curr_pt_addr <= { dcache_resp_data[53:10], 12'b0 };
                            curr_level <= curr_level - 1;


                        // === If leaf: store pte, go to done
                        end else begin
                            //ppn comes from pte
                            //if superpage, lower bits come from virt address
                            state <= MMU_DONE;
                            final_pte <= dcache_resp_data;
                        end
                    end
                end

                MMU_DONE: begin
                    // state <= MMU_IDLE
                end

                default: begin
                    $error("Unexpected state in MMU: %d", state);
                end

            endcase

        end


    end



    function logic [63:0] leafToTranslatedAddress(input logic [63:0] leaf_pte_data,
                                        input logic [3:0][8:0] vpn,
                                        input logic [3:0]  curr_level); //superpages get to keep more bits in offset

        integer i;
        reg [17:0]      ppn_3;     //highest ppn is more bits, and is always used
        reg [2:0][8:0]  ppn;       //these ppns might not all get used, depending on how big a superpage this is
        reg [2:0][8:0]  final_ppn; // these will be the ppns going into the final address

        {ppn_3[17:0], ppn[2][8:0], ppn[1][8:0], ppn[0][8:0] } = leaf_pte_data[53:10]; //decode 




        // === For each level of the address, choose to use the PPN or the original VPN 
        // === Depending on what level of superpage we're at
        for (i = 0; i < 3; i++) begin // loop over ppn[0:2]
            if (curr_level <= i) begin // we walked far enough down, this is a normal page component, just use the ppn
                final_ppn[i] = ppn[i];   


            end else begin // else this part of address falls inside superpage:
                if(ppn[i] != 0) // A: assert that the PTE we got correctly zeroed out those bits
                    $error("Superpage should be zeroed out in MMU: curr_level %d, pte %x", curr_level, leaf_pte_data);
                // B: replace that with the original vpn values 
                // (since those bits are now within the superpage offset)
                final_ppn[i] = vpn[i];
            end
        end

        return { ppn_3[17:0], final_ppn[2][8:0], final_ppn[1][8:0], final_ppn[0][8:0], 12'b0 };
    endfunction


endmodule
