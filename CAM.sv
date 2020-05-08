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
    input                   push,
    input                   pop,
    output                  empty,
    output                  full,
    input   [WIDTH-1:0]     data_in,
    output  [WIDTH-1:0]     data_out,
    input   [CAM_WIDTH-1:0] cam_data,
    output                  cam_exists
);

    reg [WIDTH-1:0]     data        [DEPTH];
    reg [DEPTH-1:0]     valid_data;
    reg [LOG_DEPTH-1:0] head;
    reg [LOG_DEPTH-1:0] tail;

    assign empty = ~|valid_data;
    assign full = &valid_data;
    assign data_out = data[head];

    // push logic
    always_ff @ (posedge clk) begin
        if (reset)
            tail <= 0;
        else if (push) begin
            data[tail] <= data_in;
            tail <= tail + 1;
            assert(!full);
        end
    end

    // pop logic
    always_ff @ (posedge clk) begin
        if (reset)
            head <= 0;
        else if (pop) begin
            head <= head + 1;
            assert(!empty);
        end
    end

    // valid_data logic
    integer i;
    always_ff @ (posedge clk) begin
        if (reset)
            for (i = 0; i < DEPTH; i = i + 1)
                valid_data[i] <= 1'b0;
        else if (push)
            valid_data[tail] <= 1'b1;
        else if (pop)
            valid_data[head] <= 1'b0;
    end

    // CAM logic
    integer j;
    always_comb begin
        cam_exists = 1'b0;
        for (j = 0; j < DEPTH; j = j + 1)
            if (valid_data[j] && cam_data == data[j][CAM_WIDTH-1:0]) begin
                cam_exists = 1'b1;
            end
    end
endmodule

`endif
