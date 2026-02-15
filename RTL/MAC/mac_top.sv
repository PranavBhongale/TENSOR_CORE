`timescale 1ns/1ps

module mac_top #(
  parameter int DATA_W = 8,
  parameter int ACC_W  = 32,
  parameter int ROWS   = 4,  // Number of PE rows
  parameter int COLS   = 4  // Number of PE columns
  // parameter int K      = 2    // Number of MAC operations to perform before outputting result
) (
  input  logic clk,
  input  logic reset_n,

  // Activation inputs (one per row)
  input  logic signed [DATA_W-1:0] act_data [ROWS],
  input  logic act_valid [ROWS],

  // Weight inputs (one per column)
  input  logic signed [DATA_W-1:0] wgt_data [COLS],
  input  logic wgt_valid [COLS],

  // Partial sum outputs (one per PE)
  output logic signed [ACC_W-1:0] psum_out [ROWS][COLS] ,
  // input logic counter_sync_in  // Optional input for synchronizing MAC counters across PEs
  input logic counter_sync_in,  // Optional input for synchronizing MAC counters across PEs

  // the signal for c_datd and c_valid
  input logic signed [ACC_W-1:0] C_data [ROWS],
  input logic C_data_valid  [ROWS],
  input logic c_lock
);

  // Internal signals for systolic array connections
  logic signed [DATA_W-1:0] act_data_array [ROWS][COLS+1];
  logic signed [DATA_W-1:0] wgt_data_array [ROWS+1][COLS];
  logic act_valid_array [ROWS][COLS+1];
  logic wgt_valid_array [ROWS+1][COLS];
  logic signed [ACC_W-1:0] C_data_array [ROWS][COLS+1];
  logic C_data_valid_array [ROWS][COLS+1];


  // Connect inputs to array edges
  always_comb begin
    for (int i = 0; i < ROWS; i++) begin
      act_data_array[i][0] = act_data[i];
      act_valid_array[i][0] = act_valid[i];
    end

    for (int j = 0; j < COLS; j++) begin
      wgt_data_array[0][j] = wgt_data[j];
      wgt_valid_array[0][j] = wgt_valid[j];
    end
  end
  always_ff @( posedge clk  ) begin : blockName
   for(int i = 0; i < ROWS; i++) begin
         C_data_array[i][0] <= C_data[i];
         C_data_valid_array[i][0] <= C_data_valid[i];
   end
  end

  // Instantiate PE array
  genvar row, col;
  generate
    for (row = 0; row < ROWS; row++) begin : gen_rows
      for (col = 0; col < COLS; col++) begin : gen_cols
        pe_top #(
          .DATA_W(DATA_W),
          .ACC_W(ACC_W)
          // .K(K)  // Each PE performs 1 MAC before outputting result
        ) pe_inst (
          .clk(clk),
          .reset_n(reset_n),
          // counter connection for synchronizing MAC counters across PEs
          .counter_sync_in(counter_sync_in),
           // Data and valid connections
           // Activations flow horizontally (left to right)
           // Weights flow vertically (top to bottom)
           // Partial sums are output after K MACs
          // Activation flows horizontally (left to right)
          .acc_data(act_data_array[row][col]),
          .acc_data_valid(act_valid_array[row][col]),
          .acc_data_next(act_data_array[row][col+1]),
          .acc_data_valid_next(act_valid_array[row][col+1]),
          // Weights flow vertically (top to bottom)
          .wet_data(wgt_data_array[row][col]),
          .wet_data_valid(wgt_valid_array[row][col]),
          .wet_data_next(wgt_data_array[row+1][col]),
          .wet_data_valid_next(wgt_valid_array[row+1][col]),
          // Partial sum output
          .psum(psum_out[row][col]),
          // C_data and C_data_valid connections
          .C_data(C_data_array[row][col]),
          .C_data_valid(C_data_valid_array[row][col]),
          .C_data_next(C_data_array[row][col+1]),
          .C_data_valid_next(C_data_valid_array[row][col+1]),
          // c_lock connection
          .c_lock(c_lock)
        );
      end
    end
  endgenerate

endmodule
