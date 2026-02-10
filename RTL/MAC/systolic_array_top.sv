
`timescale 1ns/1ps
module systolic_array_top #(
  parameter int DATA_W = 8,
  parameter int ACC_W  = 32,
  parameter int ROWS   = 8,
  parameter int COLS   = 8,
  parameter int K      = 8   // Number of MAC operations to perform before outputting result
) (
  input logic clk,
  input logic reset_n,
  output logic done,
  input logic signed [DATA_W-1:0] matrix_acc_col [COLS], // we have to feed the leftmost column of activations first
  input logic matrix_acc_valid,
  input logic signed [DATA_W-1:0] matrix_wet_row [ROWS],  //  we have to feed the bottem row of weights first
  input logic matrix_wet_valid,
  output logic signed [ACC_W-1:0] result_matrix [ROWS][COLS],
  output logic result_valid
);


logic signed [DATA_W-1:0] matrix_acc_row_array [ROWS];
logic matrix_acc_valid_array [ROWS];
logic signed [DATA_W-1:0] matrix_wet_col_array [COLS];
logic matrix_wet_valid_array [COLS];
 logic signed [ACC_W-1:0] result_matrix_valid_array [ROWS][COLS];
//  we will feed the leftmost column of activations first, and the bottom row of weights first,
// and then shift them in every cycle until the entire matrix is fed in
 logic counter_sync ;
mac_top #(
  .DATA_W(DATA_W),
  .ACC_W(ACC_W),
  .ROWS(ROWS),
  .COLS(COLS)
  // .K(K)
) mac_inst (
  .clk(clk),
  .reset_n(reset_n),
  .counter_sync_in(counter_sync),
  .act_data(matrix_acc_row_array),
  .act_valid(matrix_acc_valid_array),
  .wgt_data(matrix_wet_col_array),
  .wgt_valid(matrix_wet_valid_array),
  .psum_out(result_matrix_valid_array)
);

//  the simple approach is to make the queue for each and hardcode it
//  this is the logic for shift register
genvar i;
generate
for ( i = 1; i <= COLS; i++) begin : g_A_DELAY
  shift_register #(
    .WIDTH(DATA_W),
    .DEPTH(i)   // ← VARIABLE LENGTH
  ) A_shift (
    .clk(clk),
    .reset_n(reset_n),
    .din(matrix_wet_row[i-1]),
    .valid_in(matrix_wet_valid),
    .dout(matrix_wet_col_array[i-1]),
    .valid_out(matrix_wet_valid_array[i-1])
  );
end
endgenerate
//  this is for row   acc_data ;
genvar j;
generate
for (j = 1; j <= ROWS; j++) begin : g_B_DELAY
  shift_register #(
    .WIDTH(DATA_W),
    .DEPTH(j)   // ← VARIABLE LENGTH
  ) B_shift (
    .clk(clk),
    .reset_n(reset_n),
    .din(matrix_acc_col[j-1]),
    .valid_in(matrix_acc_valid),
    .dout(matrix_acc_row_array[j-1]),
    .valid_out(matrix_acc_valid_array[j-1])
  );
end
endgenerate


 // regester the matrix_acc_valid and matrix_wet_valid  we need this to make sure that we are feeding the data at the same cycle and also to make sure that we are not feeding the data after done is asserted
 logic matrix_acc_valid_reg;
logic matrix_wet_valid_reg;

always_ff @(posedge clk) begin
  if (!reset_n) begin
    matrix_acc_valid_reg <= 1'b0;
    matrix_wet_valid_reg <= 1'b0;
  end else begin
    // Sticky behavior
    if (matrix_acc_valid)
      matrix_acc_valid_reg <= 1'b1;

    if (matrix_wet_valid)
      matrix_wet_valid_reg <= 1'b1;
  end
end

//  we need to wait col + row cycle from first input  affter  that we need to give the output so  
 // we have to make the copunter for this which will count the cycle after the first input is fed in, and then assert done after col + row cycle
logic [7:0] cycle_counter;
always_ff @(posedge clk) begin
  if (!reset_n) begin
    cycle_counter <= '0;
    done <= 1'b0;
  end else if (matrix_acc_valid_reg && matrix_wet_valid_reg) begin
    cycle_counter <= cycle_counter + 1;
    counter_sync <= 1'b1;
    if (cycle_counter >= 8'(ROWS + COLS -2 + K)) begin
      done <= 1'b1;
      // we have to give the data
      result_valid <= 1'b1;
      result_matrix <= result_matrix_valid_array;
      cycle_counter <= 0; // Reset cycle counter after output is given
      matrix_acc_valid_reg <= 1'b0; // Reset valid flags to prevent re-triggering
      matrix_wet_valid_reg <= 1'b0; // Reset valid flags to prevent re-triggering
      counter_sync <= 1'b0;
    end
  end
end
// the condition for giving the data to systolic_array_top  we have to feed the data   for matrix at the same cycle
// it is not like we send first data and then second data  we have to send it correctly

endmodule


