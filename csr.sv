
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
    

    // Handle an exception/interrupt    
    input handle_interrupt,
    input handle_exception,
    input [63:0] save_pc,        // Write this to the correct xEPC 
    input [1:0] save_priv,

    input handle_mret,
    input handle_sret,
    input handle_uret,

    output [1:0] ret_priv,
    output [63:0] handler_addr,


    output [REG_WIDTH-1:0] csr_result, // The value to be written to rd.

    output [REG_WIDTH-1:0] mepc_csr,
    output [REG_WIDTH-1:0] satp_csr,

    output modifying_satp
);
    logic [REG_WIDTH-1:0] csrs [0:CSR_COUNT-1]; // The CSR registers

    logic [1:0] csr_rw_perm;
    logic [1:0] lowest_priv;

    assign csr_rw_perm = addr[CSR-1:CSR-2];
    assign lowest_priv = addr[CSR-3:CSR-4];

    assign csr_result = csrs[addr]; // Combinationally read CSRs
    assign mepc_csr = csrs[CSR_MEPC];
    assign satp_csr = csrs[CSR_SATP];

    assign modifying_satp = valid && is_csr && (addr == CSR_SATP);

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

        if (handle_interrupt) begin
            csrs[CSR_MEPC] <= save_pc;
            csrs[CSR_MSTATUS][12:11] <= save_priv; // set mstatus.(mpp=12:11) to privilege mode before interrupt
            csrs[CSR_MSTATUS][7] <= csrs[CSR_MSTATUS][3]; // set mstatus.(mpie=7) to mstatus.(mie=3)
            csrs[CSR_MSTATUS][3] <= 0; // set mstatus.(mie=3) = 0
            
            // handler_addr <= ; // output interrupt handler address based on mode of operation
        end

        if (handle_exception) begin
            // Not quite sure the exact steps to be taken in the event of an exception yet.
            // Probably not exactly the same as an interrupt.
        end

        if (handle_mret) begin
            // must write mepc to pc register. We already do this but maybe refactor the code to do it here
            csrs[CSR_MSTATUS][3] <= csrs[CSR_MSTATUS][7]; // set mstatus.(mie=3) to mstatus.(mpie=7)
            csrs[CSR_MSTATUS][7] <= 1; // set mstatus.(mpie=7) to 1
            ret_priv <= csrs[CSR_MSTATUS][12:11]; // output previous privilege (mstatus.(mpp=12:11))
            csrs[CSR_MSTATUS][12:11] <= PRIV_M; // Set mstatus.(mpp=12:11) to U (or M if user-mode not supported)
        end
        else if (handle_sret) begin
            // must write sepc to pc register.
            csrs[CSR_SSTATUS][3] <= csrs[CSR_SSTATUS][7]; // set sstatus.(sie=3) to sstatus.(spie=7)
            csrs[CSR_SSTATUS][7] <= 1; // set sstatus.(spie=7) to 1
            ret_priv <= csrs[CSR_SSTATUS][12:11]; // output previous privilege (sstatus.(spp=12:11))
            csrs[CSR_SSTATUS][12:11] <= PRIV_M; // Set sstatus.(spp=12:11) to U (or M if user-mode not supported)
        end
        else if (handle_uret) begin
            // must write uepc to pc register.
            csrs[CSR_USTATUS][3] <= csrs[CSR_USTATUS][7]; // set ustatus.(uie=3) to ustatus.(upie=7)
            csrs[CSR_USTATUS][7] <= 1; // set ustatus.(upie=7) to 1
            ret_priv <= csrs[CSR_USTATUS][12:11]; // output previous privilege (ustatus.(upp=12:11))
            csrs[CSR_USTATUS][12:11] <= PRIV_M; // Set ustatus.(upp=12:11) to U (or M if user-mode not supported)
        end
    end


endmodule

