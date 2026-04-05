// this module is for shifting the data in the activation block pipeline for gelu and it
// will shift the data to the right by 3 bits and then it will pass the data to the 
//next stage in the activation block pipeline


// i am chosing the shift bit as 3 because the shift  Shift should NOT be based on worst-case (127×127×K).
// It should be based on probable / statistical values.
// in the most of the cases the value of the psum will be less than 127*127*16 = 261632 and
// if we shift the data by 3 bits then we will get the value of 4096 which \
//is a reasonable value for the activation function to work with and also it will help in
// reducing the power consumption and also it will help in reducing the area of the chip.

module shift_unit #(
    parameter ACC_D = 32,
    parameter SHIFT_BITS = 3,
    /* verilator lint_off UNUSEDPARAM */
    parameter ROWS = 8 ,
    /* verilator lint_on UNUSEDPARAM */
    parameter COLS = 8
) (
    input logic clk,
    input logic reset_n,
    input logic signed [ACC_D-1:0] din[COLS],
    input logic valid_in,
    output logic signed  [ACC_D-1:0] dout[COLS],
    output logic valid_out
);

    logic signed  [ACC_D-1:0] data_pipe [COLS];
    logic valid_pipe;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
                for (int j = 0; j < COLS; j++) begin
                    data_pipe[j] <= '0;
                end
            valid_pipe <= 1'b0;
        end else begin
                for (int j = 0; j < COLS; j++) begin
                    data_pipe[j] <= din[j] >>> SHIFT_BITS; // Shift right by SHIFT_BITS
                end

            valid_pipe <= valid_in;
        end
    end

    assign dout = data_pipe;
    assign valid_out = valid_pipe;

endmodule
// In real neural networks (especially quantized INT8):

// Inputs are roughly zero-mean
// Weights are roughly zero-mean
// Values follow something like a Gaussian distribution
// So the MAC is summing random signed products.
// 👉 The magnitude grows with √K, not K (statistically).

