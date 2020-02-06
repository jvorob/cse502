
module RegFile
(
    input clk,
    input [4:0] read_addr1,
    input [4:0] read_addr2,
    input [4:0] wb_addr,
    input [63:0] wb_data,
    input wb_en,
    output [63:0] out1,
    output [63:0] out2
);
    reg [63:0] regs [0:31];

    assign out1 = read_addr1 != 5'h00 ? regs[read_addr1] : 64'h0000_0000_0000_0000;
    assign out2 = read_addr2 != 5'h00 ? regs[read_addr2] : 64'h0000_0000_0000_0000;

    always @(posedge clk) begin
        if (wb_en) regs[wb_addr] = wb_data;
    end

endmodule

