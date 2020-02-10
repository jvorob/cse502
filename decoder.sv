
/*    Decoder module and decode function
 *
 *
 *
 *
 */


module Decoder
(
    input [31:0] inst,

    output [63:0] imm, //Decoded based on which opcode

    // Which registers are used (will be set to r0 instead for certain insts)
    output [4:0] rs1,
    output [4:0] rs2,
    output [4:0] rd,
    output en_rs1, // used to enable hazard detection (turn off for r0)
    output en_rs2, // (same)

    output en_rd, // used to enable writeback, stall detection


    // ALU codes
    output [2:0] funct3,
    output [6:0] funct7,
    output [6:0] op,

    // Special Codes:
    //   Jump outputs: (TODO)
    /* == Jump-outputs (not really from decoder, but whatever)
       jump_if: (ALU1, ALU0, YES, NO)
       jump_target: (ALU_RESULT, PC_PLUS_IMMED) //(for JALR jump to result, else (brnch) jump to just the immed)
           - if branch: jump pc+immed (NOT-ALU)
           - if jal:    jump pc+immed (NOT-ALU), (but also can use ALU-ADD path with rs0)
           - if jalr:   jump rs1+immed (ALU-ADD)
     * =Branch codes:
     * BEQ, BNE    (000, 001) -> sub, jump if zero/nonzero
     * ...
     * BLT, BGE    (100, 101) -> SLT, jump if set/unset
     * BLTU, BGEU  (110, 111) -> SLTU, jump if set/unset
     */
    
    
    // == Other codes
    output keep_pc_plus_immed, //(for AUIPC, we already have a separate PC+(...) adder, just shove that into exec result
    output use_immed_alu // (ALU input B shoould b immed, not rs2)

);


    // Immediate versions (will be muxed depending on opcode)
    logic [63:0]  immed_I ; //12 bits in opcode (then sign-extend the rest)
    logic [63:0]  immed_S ; //12 bits 
    logic [63:0]  immed_SB; //13 bits 
    logic [63:0]  immed_U ; //32 bits 
    logic [63:0]  immed_UJ; //20 bits 

    // Construct these by sign-extending the top, then unscrambling the rest of it
    assign  immed_I  = { {52{inst[31]}}, inst[31:20]};
    assign  immed_S  = { {52{inst[31]}}, inst[31:                   25], inst[11:        7] };
    assign  immed_SB = { {51{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8],   1'b0 };
    assign  immed_U  = { {32{inst[31]}}, inst[31:          12],                       12'b0 };
    assign  immed_UJ = { {44{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 } ;


    // internal instruction fragments
    logic [5:0] shamt ;
    logic [11:0] csr  ;
    logic [4:0] zimm  ;
    logic [3:0] pred  ;
    logic [3:0] succ  ;





    always_comb @(inst) begin
        Opcode op_code = inst[6:0];

        // === SET DEFAULT VALUES FOR THESE:
        // will be overriden for specific instructions that need them
        assign rs1    = inst[19:15];
        assign rs2    = inst[24:20];
        assign rd     = inst[11: 7];

        assign funct3 = inst[14:12]; //TODO: override these for certain instructions
        assign funct7 = inst[31:25]; // branches, adds, etc

        assign shamt  = inst[25:20];
        assign csr    = inst[31:20];
        assign zimm   = inst[19:15];
        assign pred   = inst[27:24];
        assign succ   = inst[23:20];


        // ====== SPECIAL SIGNALS
        
        //(for AUIPC, we already compute ALU_result+PC, mux that into exec-stage result)
        assign keep_pc_plus_immed = 0;

        // ALU gets immed value instead of rs2 value
        assign use_immed_alu = 0; //inst[6:0] inside{OP_OP_IMM, OP_IMM_32, OP_LOAD, OP_STORE, OP_JAL, OP_JALR};


        //TODO: special codes:
        // - Jump/Branch codes
        // - for mem ops, need to pass rs2 or immed or whichever through
        //   non-alu path?
        // - MISC_MEM: ??? TODO
        // - SYSTEM: ??? TODO

        // === MAIN DECODER:
        // Determine immediate values, and which of rs1,rs2,and rd we're using
        // Also set special signals for appropriate things
        case (op_code) inside
            // == Unusual immeds: U UJ S SB
            OP_LUI, OP_AUIPC: begin
                imm = immed_U;
                use_immed_alu = 1; 
                rs1 = 0; //don't add anything to immed
                funct7 = 0;
                funct3 = F3OP_ADD_SUB; //ALU does 0+immed

                {en_rs1, en_rs2, en_rd } = 3'b001; // imm -> dest reg

                if(op_code == OP_AUIPC) keep_pc_plus_immed = 1; //after ALU, separate adder does +PC
            end

            // == JUMPS
            OP_JALR: begin
                imm = immed_I;
                use_immed_alu = 1; //rs1 + immed
                funct7 = 0;
                funct3 = F3OP_ADD_SUB; //ALU does 0+immed

                {en_rs1, en_rs2, en_rd } = 3'b101; // src reg + return addr
                //TODO set jump_if and jump_to
            end
            OP_JAL: begin
                imm = immed_UJ;
                rs1 = 0; 
                use_immed_alu = 1;
                funct7 = 0;
                funct3 = F3OP_ADD_SUB; //ALU does 0+immed

                {en_rs1, en_rs2, en_rd } = 3'b001; // only return addr
                //TODO set jump_if and jump_to
            end

            // == Branches
            OP_BRANCH: begin
                imm = immed_SB;
                // ALU does rs1 comp rs2
                {en_rs1, en_rs2, en_rd } = 3'b110; // test regs
                //TODO: set alu codes
                //TODO: set jump_if and jump_to
            end

            // === Load/Store
            // (both of these also set use_immed_alu so ALU can calc address)
            OP_LOAD: begin
                imm = immed_I;
                use_immed_alu = 1;
                funct7 = 0;
                funct3 = F3OP_ADD_SUB; //ALU does rs1+immed (load-addr)

                {en_rs1, en_rs2, en_rd } = 3'b101; // src mem + dest reg
            end

            OP_STORE: begin
                imm = immed_S;
                use_immed_alu = 1;
                funct7 = 0;
                funct3 = F3OP_ADD_SUB; //ALU does rs1+immed (store-addr)

                {en_rs1, en_rs2, en_rd } = 3'b110; // 2 src mem addr
                //TODO: make sure Mem gets rs2 (that's the data to be stored)
                //TODO: can optimize, we dont need rs2 until mem stage, so can loosen hazard
                // resolution slightly
            end

            // == I-type
            OP_OP_IMM, OP_IMM_32: begin
                imm = immed_I;
                use_immed_alu = 1;
                {en_rs1, en_rs2, en_rd } = 3'b101; //no rs2
                // ALU codes come from op
            end

            OP_OP, OP_OP_32: begin
                imm = 0; //doesn't use it
                {en_rs1, en_rs2, en_rd } = 3'b111; //uses all regs
                // ALU codes come from op
            end


            // ==== ETC: We dont want to implement these rn

            OP_MISC_MEM, OP_SYSTEM: begin
                imm = 0; // Might need to change this
                {en_rs1, en_rs2, en_rd } = 3'b000; // I think this is right?
            end

        endcase
    end


endmodule

//========= NOTE: old decoder: (no longer needed but parts of this will
//probably be useful later on)

 //   always_comb @(inst) begin
 //       Opcode op_code = inst[6:0];
 //       case (op_code) inside
 //           OP_LUI: begin
 //           $display("lui, r%0d, 0x%x", rd, immed_U);
 //           end
 //           OP_AUIPC: begin
 //           $display("auipc r%d, 0x%x", rd, immed_U);
 //           end
 //           OP_JAL: begin
 //           $display("jal 0x%x, return addr in r%0d'", immed_UJ, rd);
 //           end
 //           OP_JALR: begin
 //           if (funct3 != 3'b000) $error("ERROR: Invalid funct3 for JALR op, '%b'", funct3);
 //           $display("jalr 0x%x(r%0d), return addr in r%0d'", immed_I, rs1, rd);
 //           end

 //           OP_BRANCH: begin
 //           case (funct3) inside
 //               F3B_BEQ, F3B_BNE, F3B_BLT, F3B_BGE, F3B_BLTU, F3B_BGEU: begin
 //               Funct3_Branch branch_code = funct3;
 //               $display("Branch op: %s r%0d, r%0d, to 0x%x", branch_code.name, rs1, rs2, immed_SB);
 //               end
 //               default: begin
 //               $error("ERROR: Invalid funct3 for BRANCH op, '%b'", funct3);
 //               end
 //           endcase
 //           end

 //           // ===== Loads and stores
 //           OP_LOAD: begin
 //           case (funct3) inside
 //               F3LS_B :  $display("lb  r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_H :  $display("lh  r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_W :  $display("lw  r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_D :  $display("ld  r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_BU:  $display("lbu r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_HU:  $display("lhu r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               F3LS_WU:  $display("lwu r%0d, %0d(r%0d)", rd, immed_I, rs1);
 //               default: $display("Invalid funct3 '%b' for opcode=OP_LOAD", funct3);
 //           endcase
 //           end
 //           OP_STORE: begin
 //           case (funct3) inside
 //               F3LS_B :  $display("sb  r%0d, %0d(r%0d)", rs2, immed_S, rs1);
 //               F3LS_H :  $display("sh  r%0d, %0d(r%0d)", rs2, immed_S, rs1);
 //               F3LS_W :  $display("sw  r%0d, %0d(r%0d)", rs2, immed_S, rs1);
 //               F3LS_D :  $display("sd  r%0d, %0d(r%0d)", rs2, immed_S, rs1);
 //               default: $display("Invalid funct3 '%b' for opcode=OP_STORE", funct3);
 //           endcase
 //           end

 //           // ===== Main ALU OPs
 //           OP_OP_IMM: begin
 //           Funct3_Op f3op_code = funct3;
 //           case (f3op_code) inside
 //               F3OP_SLL: begin
 //               if (funct7[6:1] != 6'b00_0000) $error("ERROR: Invalid funct7 for SLLI op, '%b'", funct7[6:1]);
 //               $display("slli r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
 //               end
 //               F3OP_SRX: begin
 //               if (funct7[6:1] == 6'b00_0000)      $display("srli r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
 //               else if (funct7[6:1] == 6'b01_0000) $display("srai r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt);
 //               else $error("ERROR: Invalid funct7 for SRLI / SRAI op, '%b'", funct7[6:1]);
 //               end

 //               F3OP_ADD_SUB: $display("addi  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
 //               F3OP_SLT:     $display("slti  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
 //               F3OP_SLTU:    $display("sltiu r%0d, r%0d, 0x%x", rd, rs1, immed_I);
 //               F3OP_XOR:     $display("xori  r%0d, r%0d, 0x%x", rd, rs1, immed_I);
 //               F3OP_OR:      $display("ori   r%0d, r%0d, 0x%x", rd, rs1, immed_I); 
 //               F3OP_AND:     $display("andi  r%0d, r%0d, 0x%x", rd, rs1, immed_I);

 //           endcase
 //           end

 //           OP_OP: begin
 //           // Multiply-ops have funct7 = 000_0001
 //           if (funct7[0]) begin
 //               Funct3_Mul mul_code = funct3;
 //               if (funct7 != 7'b000_0001) $error("ERROR: Invalid funct7 for RV32M op, '%b'", funct7);

 //               $display("RV32M op: %s r%0d, r%0d, r%0d", mul_code.name(), rd, rs1, rs2);
 //           end

 //           // Normal ops have funct7 = 0?0_0000, funct7[5] set for sub, SRA
 //           else if (funct7 == 7'b000_0000) begin
 //               case (funct3) inside
 //                   F3OP_ADD_SUB: $display("add r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_SLL:     $display("sll r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_SLT:     $display("slt r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_SLTU:    $display("sltu r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_XOR:     $display("xor r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_SRX:     $display("srl r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_OR:      $display("or r%0d, r%0d, r%0d", rd, rs1, rs2); 
 //                   F3OP_AND:     $display("and r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   default:      $display("Invalid funct3 '%b' for opcode=OP_OP and funct7=7'b000_0000.", funct3);
 //               endcase
 //           end
 //           else if (funct7 == 7'b010_0000) begin
 //               case (funct3) inside
 //                   F3OP_ADD_SUB: $display("sub r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   F3OP_SRX: $display("sra r%0d, r%0d, r%0d", rd, rs1, rs2);
 //                   default: $display("Invalid funct3 '%b' for opcode=OP_OP and funct7=7'b010_0000.", funct3);
 //               endcase 
 //           end
 //           else begin
 //               $display("Invalid funct3 '%b' for opcode=OP_OP.", funct3);
 //           end
 //           end

 //           OP_IMM_32: begin
 //           Funct3_Op f3op_code = funct3;

 //           case (f3op_code) inside
 //               F3OP_ADD_SUB: $display("addiw r%0d, r%0d, 0x%x", rd, rs1, immed_I);
 //               F3OP_SLL: begin
 //               if (funct7 != 7'b000_0000) $error("ERROR: Invalid funct7 for SLLIW op, '%b'", funct7);
 //               $display("slliw r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
 //               end
 //               F3OP_SRX: begin
 //               if (funct7 == 7'b000_0000)      $display("srliw r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
 //               else if (funct7 == 7'b010_0000) $display("sraiw r%0d, r%0d, shamt: 0x%x", rd, rs1, shamt[4:0]);
 //               else $error("ERROR: Invalid funct7 for SRLIW / SRAIW op, '%b'", funct7);
 //               end
 //               default: $error("ERROR: Invalid funct3 for 64-bit immediate op, '%b'", funct3);
 //               // -- TODO: there's a bunch more of these?
 //           endcase
 //           end 

 //           OP_OP_32: begin
 //           // Multiply ops
 //           if (funct7[0]) begin
 //               if (funct7 != 7'b000_0001) $error("ERROR: Invalid funct7 for RV64M op, '%b'", funct7);
 //               case (funct3) inside
 //               F3M_MUL, F3M_DIV, F3M_DIVU, F3M_REM, F3M_REMU: begin
 //                   Funct3_Mul mul_code = funct3;
 //                   $display("RV64M op: %sW,  r%0d, r%0d, r%0d", mul_code.name(), rd, rs1, rs2);
 //               end
 //               default: $error("ERROR: Invalid funct3 for RV64M op, '%b'", funct3);
 //               endcase

 //           // Normal ops
 //           end else begin
 //           Funct3_Op f3op_code = funct3;
 //           case (f3op_code) inside
 //               F3OP_ADD_SUB: begin
 //               if (funct7 == 7'b000_0000) $display("addw r%0d, r%0d, r%0d", rd, rs1, rs2);
 //               else if (funct7 == 7'b010_0000) $display("subw r%0d, r%0d, r%0d", rd, rs1, rs2);
 //               else $error("ERROR: Invalid funct7 for ADDW / SUBW op, '%b'", funct7);
 //               end
 //               F3OP_SLL: begin
 //               if (funct7 != 7'b000_0000) $error("ERROR: Invalid funct7 for SLLW op, '%b'", funct7);
 //               $display("sllw r%0d, r%0d, r%0d", rd, rs1, rs2);
 //               end
 //               F3OP_SRX: begin
 //               if (funct7 == 7'b000_0000) $display("SRLW r%0d, r%0d, r%0d", rd, rs1, rs2);
 //               else if (funct7 == 7'b010_0000) $display("SRAW r%0d, r%0d, r%0d", rd, rs1, rs2);
 //               else $error("ERROR: Invalid funct7 for SRLW / SRAW op, '%b'", funct7);
 //               end
 //               // -- TODO: there's a bunch more of these?
 //           endcase
 //           end
 //           end

 //           // ===== Misc Ops (mem, system)

 //           OP_MISC_MEM: begin
 //           if (rd == 0 && funct3 == F3F_FENCE && rs1 == 0 && immed_I[11:8] == 0) begin
 //               $display("fence pred=%0d, pred=%0d", immed_I[7:4], immed_I[3:0]);
 //           end
 //           else if (rd == 0 && funct3 == F3F_FENCE_I && rs1 == 0 && immed_I == 0) begin
 //               $display("fence.i");
 //           end else begin
 //               $display("Invalid instruction for opcode=OP_MISC_MEM.");
 //           end
 //           end

 //           OP_SYSTEM: begin
 //           case (funct3) inside
 //               F3SYS_ECALL_EBREAK: begin
 //                   if (immed_I[0] == 0)
 //                       $display("ecall");
 //                   else if (immed_I[0] == 1)
 //                       $display("ebreak");
 //                   else
 //                       $display("Invalid instruction for opcode=OP_SYSTEM and funct3=F3_ECALL_EBREAK.");
 //               end
 //               F3SYS_CSRRW: begin
 //                   $display("csrrw rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
 //               end
 //               F3SYS_CSRRS: begin
 //                   $display("csrrs rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
 //               end
 //               F3SYS_CSRRC: begin
 //                   $display("csrrc rd=r%0d, rs1=r%0d, csr=r%0d", rd, rs1, csr);
 //               end
 //               F3SYS_CSRRWI: begin
 //                   $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
 //               end
 //               F3SYS_CSRRSI: begin
 //                   $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
 //               end
 //               F3SYS_CSRRCI: begin
 //                   $display("csrrw rd=r%0d, zimm=r%0d, csr=r%0d", rd, zimm, csr);
 //               end
 //               default: $display("Invalid instruction for opcode=OP_SYSTEM.");
 //           endcase
 //           end

 //           default: begin
 //           $display("\n");
 //           $display("Decoding instruction %b ", inst);

 //           $display("Not recognized instruction.");
 //           $display("got opcode %s ('%b\')", op_code.name(), op_code);

 //           $display(" I-Immed is %x (%b)", immed_I, immed_I);
 //           $display(" S-Immed is %x (%b)", immed_S, immed_S);
 //           $display("SB-Immed is %x (%b)", immed_SB, immed_SB);
 //           $display(" U-Immed is %x (%b)", immed_U, immed_U);
 //           $display("UJ-Immed is %x (%b)", immed_UJ, immed_UJ);
 //           end
 //       endcase
 //   end
