//  this is the module of rome  which contain the look up table for the gelu function and it will take the 
//input of the data from the clamp unit and then it will output the data to the next stage in the activation 
//block pipeline.

module Look_Table #(
    parameter ROWS = 8,
    parameter COLS = 8
)(
    input  logic                          clk,
    input  logic                          reset_n,
    input  logic                          valid_in,
    input  logic signed [7:0]             din   [COLS],
    output logic signed [7:0]            dout  [COLS],
    output logic                          valid_out
);



always_ff @(posedge clk ) begin
 if(!reset_n) begin
    valid_out <= '0;
 end  else begin
    valid_out <= valid_in ;
 end
end



    // Instantiate 8 LUTs using generate
    genvar i;
generate
    for (i = 0; i < ROWS; i++) begin : g_row_loop
       gelu_lut  dut (
            .clk(clk),
            .addr_1(din[i]), // Assuming all columns in the same row have the same input for simplicity
            .dout_1(dout[i]) // Output for the first column, can be replicated for others
        );
    end
endgenerate

endmodule

