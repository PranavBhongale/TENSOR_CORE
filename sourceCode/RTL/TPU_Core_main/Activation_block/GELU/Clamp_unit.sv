// this module bring the data from the matrix and then  it will clamp the data to the range of 0 to 127 and then 
//it will pass the data to the next stage in the activation block pipeline.

module Clamp_unit #(
    parameter ACC_D = 32,
    parameter CLAMP_MIN = -128,
    parameter CLAMP_MAX = 127,
    parameter CLAMP_SIZE = 8, // number of bits to represent the clamped value;
/* verilator lint_off UNUSEDPARAM */
    parameter ROWS = 8 ,
/* verilator lint_on UNUSEDPARAM */
    parameter COLS = 8
) (
    input logic clk,
    input logic reset_n,
    input logic signed  [ACC_D-1:0] din[COLS],
    input logic valid_in,
    output logic signed  [CLAMP_SIZE-1:0] dout[COLS],
    output logic valid_out
);



    logic signed [ACC_D-1:0] data_pipe[COLS];
    logic valid_pipe;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            for(int i = 0 ; i < COLS; i++) begin
                data_pipe[i] <= '0;
            end
            valid_pipe <= 1'b0;
        end else begin
            for(int i = 0 ; i < COLS; i++) begin
                data_pipe[i] <= din[i];
            end
            valid_pipe <= valid_in;
        end
    end

    always_comb begin
        for (int j = 0; j < COLS; j++) begin
            if (data_pipe[j] < CLAMP_MIN)
                dout[j] = 8'(CLAMP_MIN);
            else if (data_pipe[j] > CLAMP_MAX)
                dout[j] = 8'(CLAMP_MAX);
            else
                dout[j] = data_pipe[j][CLAMP_SIZE-1:0]; // Take the lower bits if within range
        end
    end

    assign valid_out = valid_pipe;


endmodule
