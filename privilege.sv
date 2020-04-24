
// Currently, traps and exceptions aren't supported in our processor,
// so we won't do anything when CSRs are accessed inappropriately.
module Privilege_System
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
    input trap_en,
    input [63:0] trap_cause,           // 1 = interrupt, 0 = exception
    input [63:0] trap_pc,       // Write this to the correct xEPC
    input [63:0] trap_mtval,

    input trap_is_ret,
    input [1:0] trap_ret_from_priv,

    output jump_trap_handler,
    output [63:0] handler_addr,

    output [REG_WIDTH-1:0] csr_result, // The value to be written to rd.

    output is_xret,
    output [REG_WIDTH-1:0] epc_addr,
    output [REG_WIDTH-1:0] satp_csr,

    output modifying_satp,
    output [1:0] curr_priv_mode
);
    logic [1:0] current_mode;   // Current privilege mode
    logic [REG_WIDTH-1:0] csrs [0:CSR_COUNT-1]; // The CSR registers

    logic [1:0] csr_rw_perm;
    logic [1:0] lowest_priv;

    assign csr_rw_perm = addr[CSR-1:CSR-2];
    assign lowest_priv = addr[CSR-3:CSR-4];

    assign csr_result = csrs[addr]; // Combinationally read CSRs
    assign satp_csr = csrs[CSR_SATP];

    logic is_interrupt;
    assign is_interrupt = trap_cause[63];

    assign curr_priv_mode = current_mode;
    assign modifying_satp = valid && is_csr && (addr == CSR_SATP);

    always_ff @(posedge clk) begin
        if (reset) begin
            csrs <= '{default:0};
            current_mode <= PRIV_M;
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

        if (trap_en) begin
            csrs[CSR_MEPC] <= trap_pc;
            csrs[CSR_MSTATUS][12:11] <= current_mode; // set mstatus.(mpp=12:11) to privilege mode before interrupt
            csrs[CSR_MSTATUS][7] <= csrs[CSR_MSTATUS][3]; // set mstatus.(mpie=7) to mstatus.(mie=3)
            csrs[CSR_MSTATUS][3] <= 0; // set mstatus.(mie=3) = 0
            

            csrs[CSR_MCAUSE] <= trap_cause;
            csrs[CSR_MTVAL] <= trap_mtval;

            // New privilege mode is M by default on trap (check medeleg and mideleg to delegate)
            current_mode <= PRIV_M;
        end
        
        if (trap_is_ret) begin
            if (trap_ret_from_priv == PRIV_M) begin
                // must write mepc to pc register. We already do this but maybe refactor the code to do it here
                csrs[CSR_MSTATUS][3] <= csrs[CSR_MSTATUS][7]; // set mstatus.(mie=3) to mstatus.(mpie=7)
                csrs[CSR_MSTATUS][7] <= 1; // set mstatus.(mpie=7) to 1
                current_mode <= csrs[CSR_MSTATUS][12:11]; // output previous privilege (mstatus.(mpp=12:11))
                csrs[CSR_MSTATUS][12:11] <= PRIV_M; // Set mstatus.(mpp=12:11) to U (or M if user-mode not supported)
            end
            else if (trap_ret_from_priv == PRIV_S) begin
                // must write sepc to pc register.
                csrs[CSR_SSTATUS][3] <= csrs[CSR_SSTATUS][7]; // set sstatus.(sie=3) to sstatus.(spie=7)
                csrs[CSR_SSTATUS][7] <= 1; // set sstatus.(spie=7) to 1
                current_mode <= csrs[CSR_SSTATUS][12:11]; // output previous privilege (sstatus.(spp=12:11))
                csrs[CSR_SSTATUS][12:11] <= PRIV_M; // Set sstatus.(spp=12:11) to U (or M if user-mode not supported)
            end
            else if (trap_ret_from_priv == PRIV_U) begin
                // must write uepc to pc register.
                csrs[CSR_USTATUS][3] <= csrs[CSR_USTATUS][7]; // set ustatus.(uie=3) to ustatus.(upie=7)
                csrs[CSR_USTATUS][7] <= 1; // set ustatus.(upie=7) to 1
                current_mode <= csrs[CSR_USTATUS][12:11]; // output previous privilege (ustatus.(upp=12:11))
                csrs[CSR_USTATUS][12:11] <= PRIV_M; // Set ustatus.(upp=12:11) to U (or M if user-mode not supported)
            end
        end
    end

    always_comb begin
        if (trap_en)
            jump_trap_handler = 1;
        else
            jump_trap_handler = 0;


        if (csrs[CSR_MTVEC][1:0] == 0) begin        // Direct
            handler_addr = { csrs[CSR_MTVEC][63:2], 2'b00 };
        end
        else if (csrs[CSR_MTVEC][1:0] == 1) begin   // Vectored
            if (is_interrupt == 0)
                handler_addr = { csrs[CSR_MTVEC][63:2], 2'b00 };
            else
                handler_addr = { csrs[CSR_MTVEC][63:2], 2'b00 } + ( { 1'b0, csrs[CSR_MCAUSE][62:0] } << 2);
        end
        else begin
            $display("CSR MTVEC mode is an invalid value: 0x%x", csrs[CSR_MTVEC][1:0]);
        end
    end

    always_comb begin
        is_xret = trap_is_ret;
        if (trap_is_ret) begin
            if (trap_ret_from_priv == PRIV_M) begin
                epc_addr = csrs[CSR_MEPC];
            end
            else if (trap_ret_from_priv == PRIV_S) begin
                epc_addr = csrs[CSR_SEPC];
            end
            else if (trap_ret_from_priv == PRIV_U) begin
                epc_addr = csrs[CSR_UEPC];
            end
            else begin
                epc_addr = 0;
            end
        end
        else begin
            epc_addr = 0;
        end
    end

endmodule

