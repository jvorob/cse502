
// === Enums of useful binary constants used in decoding and elsewhere
//
// funct3 has different meanings in different contexts, so all f3 enum values
// are prefixed (F3OP for ops, F3B for branches, etc)


// =============================================
//
//             INTERNAL CODES ENUMS
//
// =============================================

// AXI Enums
typedef enum bit[1:0] {
	FIXED		= 2'b00,
	INCR		= 2'b01,
	WRAP		= 2'b10,
	RESERVED	= 2'b11
} AxBURST; // ARBURST or AWBURST


// == Enables branch, conditionally or unconditionally
typedef enum bit[1:0] {
    JUMP_NO      = 2'b00,
    JUMP_YES     = 2'b01,
    JUMP_ALU_EQZ = 2'b10,
    JUMP_ALU_NEZ = 2'b11
} Jump_Code;


// Register name mappings
typedef enum bit[4:0] {
    ZERO = 5'd0,
    RA   = 5'd1,
    SP   = 5'd2,
    GP   = 5'd3,
    TP   = 5'd4,
    
    T0   = 5'd5,
    T1   = 5'd6,
    T2   = 5'd7,

    S0   = 5'd8,
    S1   = 5'd9,
    
    A0   = 5'd10,
    A1   = 5'd11,

    A2   = 5'd12,
    A3   = 5'd13,
    A4   = 5'd14,
    A5   = 5'd15,
    A6   = 5'd16,
    A7   = 5'd17,

    S2   = 5'd18,
    S3   = 5'd19,
    S4   = 5'd20,
    S5   = 5'd21,
    S6   = 5'd22,
    S7   = 5'd23,
    S8   = 5'd24,
    S9   = 5'd25,
    S10  = 5'd26,
    S11  = 5'd27,

    T3   = 5'd28,
    T4   = 5'd29,
    T5   = 5'd30,
    T6   = 5'd31
} registers;

// s0/fp are the same register
typedef enum bit[4:0] {
    FP   = 5'd8
} registers_alt_names;

// Floating-Point registers
typedef enum bit[4:0] {
    F_T0    = 5'd0,
    F_T1    = 5'd1,
    F_T2    = 5'd2,
    F_T3    = 5'd3,
    F_T4    = 5'd4,
    F_T5    = 5'd5,
    F_T6    = 5'd6,
    F_T7    = 5'd7,

    F_S0    = 5'd8,
    F_S1    = 5'd9,

    F_A0    = 5'd10,
    F_A1    = 5'd11,

    F_A2    = 5'd12,
    F_A3    = 5'd13,
    F_A4    = 5'd14,
    F_A5    = 5'd15,
    F_A6    = 5'd16,
    F_A7    = 5'd17,

    F_S2    = 5'd18,
    F_S3    = 5'd19,
    F_S4    = 5'd20,
    F_S5    = 5'd21,
    F_S6    = 5'd22,
    F_S7    = 5'd23,
    F_S8    = 5'd24,
    F_S9    = 5'd25,
    F_S10   = 5'd26,
    F_S11   = 5'd27,

    F_T8    = 5'd28,
    F_T9    = 5'd29,
    F_T10   = 5'd30,
    F_T11   = 5'd31
} fp_registers;



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
    F3LS_WU       = 3'b110
} Funct3_LoadStore;

