
// === Enums of useful binary constants used in decoding and elsewhere
//
// funct3 has different meanings in different contexts, so all f3 enum values
// are prefixed (F3OP for ops, F3B for branches, etc)


// =============================================
//
//             INTERNAL CODES ENUMS
//
// =============================================


// == Enables branch, conditionally or unconditionally
typedef enum bit[1:0] {
    JUMP_NO      = 2'b00,
    JUMP_YES     = 2'b01,
    JUMP_ALU_EQZ = 2'b10,
    JUMP_ALU_NEZ = 2'b11
} Jump_Code;


// =============================================
//
//           INSTRUCTION DECODING ENUMS

// =============================================

typedef enum bit[6:0] {
    OP_LOAD       = 7'b0000011 ,
    OP_LOAD_FP    = 7'b0000111 , // not used
    OP_CUSTOM0    = 7'b0001011 , // not used
    OP_MISC_MEM   = 7'b0001111 ,
    OP_OP_IMM     = 7'b0010011 ,
    OP_AUIPC      = 7'b0010111 ,
    OP_IMM_32     = 7'b0011011 ,
    OP_RSRVD1     = 7'b0011111 , // not used
    
    OP_STORE      = 7'b0100011 ,
    OP_STORE_FP   = 7'b0100111 , // not used
    OP_CUSTOM1    = 7'b0101011 , // not used
    OP_AMO        = 7'b0101111 , // not used
    OP_OP         = 7'b0110011 ,
    OP_LUI        = 7'b0110111 ,
    OP_OP_32      = 7'b0111011 ,
    OP_RSRVD2     = 7'b0111111 , // not used
    
    OP_MADD       = 7'b1000011 , // not used
    OP_MSUB       = 7'b1000111 , // not used
    OP_NMSUB      = 7'b1001011 , // not used
    OP_NMADD      = 7'b1001111 , // not used
    OP_OP_FP      = 7'b1010011 , // not used
    OP_RSRVD3     = 7'b1010111 , // not used
    OP_CUSTOM2    = 7'b1011011 , // not used
    OP_RSRVD4     = 7'b1011111 , // not used
    
    OP_BRANCH     = 7'b1100011 ,
    OP_JALR       = 7'b1100111 ,
    OP_RSRVD5     = 7'b1101011 ,
    OP_JAL        = 7'b1101111 ,
    OP_SYSTEM     = 7'b1110011 ,
    OP_RSRVD6     = 7'b1110111 , // not used
    OP_CUSTOM3    = 7'b1111011 , // not used
    OP_RSRVD7     = 7'b1111111   // not used
} Opcode;

// Values of F3 for branches
typedef enum bit[2:0] {
    F3B_BEQ  = 3'b000,
    F3B_BNE  = 3'b001,
    F3B_BLT  = 3'b100,
    F3B_BGE  = 3'b101,
    F3B_BLTU = 3'b110,
    F3B_BGEU = 3'b111
} Funct3_Branch;

// Values of F3 for most ALU ops
//  (same ones for for reg-reg, reg-imm, and -W versions of instruction)
typedef enum bit[2:0] {
    F3OP_ADD_SUB  = 3'b000,
    F3OP_SLL      = 3'b001,
    F3OP_SLT      = 3'b010,
    F3OP_SLTU     = 3'b011,
    F3OP_XOR      = 3'b100,
    F3OP_SRX      = 3'b101, // SRL/SRA
    F3OP_OR       = 3'b110,
    F3OP_AND      = 3'b111
} Funct3_Op;


// Values of F3 for Mul ops (RV32M and RV64M)
typedef enum bit[2:0] {
    F3M_MUL    = 3'b000,
    F3M_MULH   = 3'b001,
    F3M_MULHSU = 3'b010,
    F3M_MULHU  = 3'b011,
    F3M_DIV    = 3'b100,
    F3M_DIVU   = 3'b101,
    F3M_REM    = 3'b110,
    F3M_REMU   = 3'b111
} Funct3_Mul;


// Values of F3 for fence instructions
typedef enum bit[2:0] {
    F3F_FENCE    = 3'b000,
    F3F_FENCE_I  = 3'b001
} Funct3_Fence;

// Values of F3 for system instructions
typedef enum bit[2:0] {
    F3SYS_ECALL_EBREAK = 3'b000,
    F3SYS_CSRRW        = 3'b001,
    F3SYS_CSRRS        = 3'b010,
    F3SYS_CSRRC        = 3'b011,
    F3SYS_CSRRWI       = 3'b101,
    F3SYS_CSRRSI       = 3'b110,
    F3SYS_CSRRCI       = 3'b111
} Funct3_System;

// Values of F3 for load/store instructions
// byte, hword, word, dword
// default is sign-extend, U is zero-extend
typedef enum bit[2:0] {
    F3LS_B        = 3'b000,
    F3LS_H        = 3'b001,
    F3LS_W        = 3'b010,
    F3LS_D        = 3'b011,
    F3LS_BU       = 3'b100,
    F3LS_HU       = 3'b101,
    F3LS_WU       = 3'b110,
    F3LS_DU       = 3'b111
} Funct3_LoadStore;
