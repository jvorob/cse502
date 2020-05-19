`ifndef CAM
`define CAM

module CAM
#(
    WIDTH = 59,
    CAM_WIDTH = 58, 
    DEPTH = 4,
    LOG_DEPTH = 2
)
(
    input                   clk,
    input                   reset,
    output                  full,
    input                   push,
    input                   pop,
    output  [LOG_DEPTH-1:0] push_index,
    input   [LOG_DEPTH-1:0] pop_index,
    input   [WIDTH-1:0]     data_in,
    output  [WIDTH-1:0]     data_out,
    input   [CAM_WIDTH-1:0] cam_data,
    output                  cam_exists
);

    reg [WIDTH-1:0] data[DEPTH];
    reg [DEPTH-1:0] valid_data;

    assign full = &valid_data;
    assign data_out = data[pop_index];

    genvar i;
    generate for (i = 0; i < DEPTH; i = i + 1)
    always_ff @ (posedge clk) begin
        if (reset)
            valid_data[i] <= 1'b0;
        else if (pop && pop_index == i) begin
            assert(valid_data[i]);
            valid_data[i] <= 1'b0;
        end else if (push && push_index == i) begin
            assert(!valid_data[i]);
            valid_data[i] <= 1'b1;
            data[i] <= data_in;
        end
    end
    endgenerate

    // CAM logic
    integer j;
    always_comb begin
        cam_exists = 1'b0;
        for (j = 0; j < DEPTH; j = j + 1)
            if (valid_data[j] && cam_data == data[j][CAM_WIDTH-1:0])
                cam_exists = 1'b1;
    end

    // push_index logic
    integer k;
    always_comb begin
        push_index = 0;
        for (k = 0; k < DEPTH; k = k + 1)
            if (!valid_data[k])
                push_index = k;
    end
endmodule

`endif
