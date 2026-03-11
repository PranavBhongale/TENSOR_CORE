//this is implimentation of ReLU function,
// which is used in neural networks as an activation function.
// ReLU stands for Rectified Linear Unit,
//and it is defined as f(x) = max(0, x).
// This means that if the input x is less than 0,
//the output will be 0, and if the input x is greater
// than or equal to 0, the output will be x itself.
// The ReLU function is commonly used in deep learning models because it
//helps to introduce non-linearity into the model while also being
// computationally efficient.

`timescale 1ns/1ps

module ReLU #(
    parameter WIDTH = 32,
    parameter  ROW =  8,
    parameter  COL =  8


) (
    input logic clk,
    input logic reset_n,
   input logic signed [WIDTH-1:0] in_data [ROW][COL],
   input logic in_valid,
    output logic signed [WIDTH-1:0] out_data [ROW][COL],
    output logic out_valid,
    output logic done
);

//  combinationla RELU function
// as we have signed data so synthesizer is smart enough to 
//know that if the MSB is 1 then the number is negative and we
// can just check the MSB to determine if the number is negative 
//or not, so we don't need to do a full comparison with 0, we can
//just check the MSB and if it's 1 then we can set the output to 0,
// if we dont have signed data it will create full subtractor comparator which is to big


// otherwise we can set the output to the input value, this will save 
//us some logic and make our design more efficient
always_comb begin
    for (int i = 0; i < ROW; i++) begin
        for (int j = 0; j < COL; j++) begin
            if (in_data[i][j] < 0) begin
                out_data[i][j] = 0;
            end else begin
                out_data[i][j] = in_data[i][j];
            end
        end
    end
end
endmodule
// now i am not intigrating the GELU type of activation this is t costly and we
// dont need it for our design as we are using ReLU as our activation function,
// if we want to use GELU we can just replace the combinational logic with the GELU
// function which is defined as f(x) = 0.5 * x * (1 + tanh(sqrt(2 / pi) * (x + 0.044715 * x^3))) 
//this will give us a smoother activation function which can help with training deep neural networks
// but it will also increase the complexity of our design and we want to keep our design as simple as 
//possible while still achieving good performance.
