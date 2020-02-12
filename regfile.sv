
module RegFile
(
    input clk,
    input reset,
    input [4:0] read_addr1,
    input [4:0] read_addr2,
    input [4:0] wb_addr,
    input [63:0] wb_data,
    input wb_en,
    output [63:0] out1,
    output [63:0] out2
);
    reg [63:0] regs [0:31];
    integer i;

    assign out1 = read_addr1 != 5'h00 ? regs[read_addr1] : 64'h0000_0000_0000_0000;
    assign out2 = read_addr2 != 5'h00 ? regs[read_addr2] : 64'h0000_0000_0000_0000;

    always_ff @(posedge clk) begin
        if (reset)
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 64'h0000_0000_0000_0000;
        else if (wb_en)
            if (wb_addr == 0)
                regs[wb_addr] <= 0; // not actually needed, but it makes debugging a little cleaner
            else
                regs[wb_addr] <= wb_data;
    end

endmodule

