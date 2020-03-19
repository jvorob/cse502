    function reg [LRU_LEN-1:0] new_lru (input reg [LRU_LEN-1:0] old_lru, input int mru);
        parameter LRU_LEN = 5; // 5 bit is enough for 4-way
        case(old_lru)
        5'b00000: begin
            case(mru)
            2'b00: new_lru = 5'b00000;
            2'b01: new_lru = 5'b00000;
            2'b10: new_lru = 5'b00000;
            2'b11: new_lru = 5'b00000;
            endcase
        end
        5'b00001: begin
            case(mru)
            2'b00: new_lru = 5'b11001;
            2'b01: new_lru = 5'b11000;
            2'b10: new_lru = 5'b10001;
            2'b11: new_lru = 5'b00001;
            endcase
        end
        5'b00010: begin
            case(mru)
            2'b00: new_lru = 5'b10110;
            2'b01: new_lru = 5'b10010;
            2'b10: new_lru = 5'b10100;
            2'b11: new_lru = 5'b00010;
            endcase
        end
        5'b00011: begin
            case(mru)
            2'b00: new_lru = 5'b10111;
            2'b01: new_lru = 5'b10011;
            2'b10: new_lru = 5'b00011;
            2'b11: new_lru = 5'b00100;
            endcase
        end
        5'b00100: begin
            case(mru)
            2'b00: new_lru = 5'b11001;
            2'b01: new_lru = 5'b11000;
            2'b10: new_lru = 5'b10100;
            2'b11: new_lru = 5'b00100;
            endcase
        end
        5'b00101: begin
            case(mru)
            2'b00: new_lru = 5'b00101;
            2'b01: new_lru = 5'b00101;
            2'b10: new_lru = 5'b00101;
            2'b11: new_lru = 5'b00101;
            endcase
        end
        5'b00110: begin
            case(mru)
            2'b00: new_lru = 5'b10110;
            2'b01: new_lru = 5'b10010;
            2'b10: new_lru = 5'b10001;
            2'b11: new_lru = 5'b00110;
            endcase
        end
        5'b00111: begin
            case(mru)
            2'b00: new_lru = 5'b10111;
            2'b01: new_lru = 5'b10011;
            2'b10: new_lru = 5'b00111;
            2'b11: new_lru = 5'b00001;
            endcase
        end
        5'b01000: begin
            case(mru)
            2'b00: new_lru = 5'b10110;
            2'b01: new_lru = 5'b11000;
            2'b10: new_lru = 5'b10100;
            2'b11: new_lru = 5'b01000;
            endcase
        end
        5'b01001: begin
            case(mru)
            2'b00: new_lru = 5'b11001;
            2'b01: new_lru = 5'b10010;
            2'b10: new_lru = 5'b10001;
            2'b11: new_lru = 5'b01001;
            endcase
        end
        5'b01010: begin
            case(mru)
            2'b00: new_lru = 5'b01010;
            2'b01: new_lru = 5'b01010;
            2'b10: new_lru = 5'b01010;
            2'b11: new_lru = 5'b01010;
            endcase
        end
        5'b01011: begin
            case(mru)
            2'b00: new_lru = 5'b11011;
            2'b01: new_lru = 5'b01011;
            2'b10: new_lru = 5'b00011;
            2'b11: new_lru = 5'b00010;
            endcase
        end
        5'b01100: begin
            case(mru)
            2'b00: new_lru = 5'b10111;
            2'b01: new_lru = 5'b11100;
            2'b10: new_lru = 5'b01100;
            2'b11: new_lru = 5'b00100;
            endcase
        end
        5'b01101: begin
            case(mru)
            2'b00: new_lru = 5'b11101;
            2'b01: new_lru = 5'b10011;
            2'b10: new_lru = 5'b01101;
            2'b11: new_lru = 5'b00001;
            endcase
        end
        5'b01110: begin
            case(mru)
            2'b00: new_lru = 5'b11110;
            2'b01: new_lru = 5'b01110;
            2'b10: new_lru = 5'b00011;
            2'b11: new_lru = 5'b00010;
            endcase
        end
        5'b01111: begin
            case(mru)
            2'b00: new_lru = 5'b01111;
            2'b01: new_lru = 5'b01111;
            2'b10: new_lru = 5'b01111;
            2'b11: new_lru = 5'b01111;
            endcase
        end
        5'b10000: begin
            case(mru)
            2'b00: new_lru = 5'b10000;
            2'b01: new_lru = 5'b10000;
            2'b10: new_lru = 5'b10000;
            2'b11: new_lru = 5'b10000;
            endcase
        end
        5'b10001: begin
            case(mru)
            2'b00: new_lru = 5'b11101;
            2'b01: new_lru = 5'b11100;
            2'b10: new_lru = 5'b10001;
            2'b11: new_lru = 5'b00001;
            endcase
        end
        5'b10010: begin
            case(mru)
            2'b00: new_lru = 5'b11110;
            2'b01: new_lru = 5'b10010;
            2'b10: new_lru = 5'b01100;
            2'b11: new_lru = 5'b00010;
            endcase
        end
        5'b10011: begin
            case(mru)
            2'b00: new_lru = 5'b11011;
            2'b01: new_lru = 5'b10011;
            2'b10: new_lru = 5'b00011;
            2'b11: new_lru = 5'b01000;
            endcase
        end
        5'b10100: begin
            case(mru)
            2'b00: new_lru = 5'b11101;
            2'b01: new_lru = 5'b11100;
            2'b10: new_lru = 5'b10100;
            2'b11: new_lru = 5'b00100;
            endcase
        end
        5'b10101: begin
            case(mru)
            2'b00: new_lru = 5'b10101;
            2'b01: new_lru = 5'b10101;
            2'b10: new_lru = 5'b10101;
            2'b11: new_lru = 5'b10101;
            endcase
        end
        5'b10110: begin
            case(mru)
            2'b00: new_lru = 5'b10110;
            2'b01: new_lru = 5'b01110;
            2'b10: new_lru = 5'b01101;
            2'b11: new_lru = 5'b00110;
            endcase
        end
        5'b10111: begin
            case(mru)
            2'b00: new_lru = 5'b10111;
            2'b01: new_lru = 5'b01011;
            2'b10: new_lru = 5'b00111;
            2'b11: new_lru = 5'b01001;
            endcase
        end
        5'b11000: begin
            case(mru)
            2'b00: new_lru = 5'b11110;
            2'b01: new_lru = 5'b11000;
            2'b10: new_lru = 5'b01100;
            2'b11: new_lru = 5'b01000;
            endcase
        end
        5'b11001: begin
            case(mru)
            2'b00: new_lru = 5'b11001;
            2'b01: new_lru = 5'b01110;
            2'b10: new_lru = 5'b01101;
            2'b11: new_lru = 5'b01001;
            endcase
        end
        5'b11010: begin
            case(mru)
            2'b00: new_lru = 5'b11010;
            2'b01: new_lru = 5'b11010;
            2'b10: new_lru = 5'b11010;
            2'b11: new_lru = 5'b11010;
            endcase
        end
        5'b11011: begin
            case(mru)
            2'b00: new_lru = 5'b11011;
            2'b01: new_lru = 5'b01011;
            2'b10: new_lru = 5'b00111;
            2'b11: new_lru = 5'b00110;
            endcase
        end
        5'b11100: begin
            case(mru)
            2'b00: new_lru = 5'b11011;
            2'b01: new_lru = 5'b11100;
            2'b10: new_lru = 5'b01100;
            2'b11: new_lru = 5'b01000;
            endcase
        end
        5'b11101: begin
            case(mru)
            2'b00: new_lru = 5'b11101;
            2'b01: new_lru = 5'b01011;
            2'b10: new_lru = 5'b01101;
            2'b11: new_lru = 5'b01001;
            endcase
        end
        5'b11110: begin
            case(mru)
            2'b00: new_lru = 5'b11110;
            2'b01: new_lru = 5'b01110;
            2'b10: new_lru = 5'b00111;
            2'b11: new_lru = 5'b00110;
            endcase
        end
        5'b11111: begin
            case(mru)
            2'b00: new_lru = 5'b11111;
            2'b01: new_lru = 5'b11111;
            2'b10: new_lru = 5'b11111;
            2'b11: new_lru = 5'b11111;
            endcase
        end
        endcase
    endfunction
