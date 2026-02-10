`timescale 1ns/1ps

module pe_top #(
  parameter int DATA_W = 8,
  parameter int ACC_W  = 32
  // parameter int K      = 2    // Number of MAC operations to perform before outputting result
) (
  // inputs from array
  input  logic signed [DATA_W-1:0] acc_data,
  input  logic signed [DATA_W-1:0] wet_data,
  // clock & reset
  input  logic clk,
  input  logic reset_n,
  // outputs to next PE (NEXT CYCLE)
  output logic signed [DATA_W-1:0] acc_data_next,
  output logic signed [DATA_W-1:0] wet_data_next,
  // VALID signals
  input  logic acc_data_valid,
  input  logic wet_data_valid,
  // propagate VALID to next PE
  output logic acc_data_valid_next,
  output logic wet_data_valid_next,
  // matrix multiply output
  output logic signed [ACC_W-1:0] psum,
  // input logic for counter synchronization
  input logic counter_sync_in
);

 

  always_ff @(posedge clk) begin
    if (!reset_n) begin
      acc_data_next <= '0;
      wet_data_next <= '0;
      acc_data_valid_next <= 1'b0;
      wet_data_valid_next <= 1'b0;
      psum <= '0;
    end else begin
      // Register activation data
      if (acc_data_valid) begin
        acc_data_next <= acc_data;
        acc_data_valid_next <= 1'b1;
      end else begin
        acc_data_valid_next <= 1'b0;
      end

      // Register weight data
      if (wet_data_valid) begin
         wet_data_next <= wet_data;
        wet_data_valid_next <= 1'b1;
      end else begin
        wet_data_valid_next <= 1'b0;
      end
      // Accumulate when both are valid
      if (acc_data_valid && wet_data_valid) begin
        psum <= psum + (acc_data * wet_data);
      end else begin
         if(!counter_sync_in) begin
           psum <= 0; // Reset accumulator when MAC is done
         end
      end
    end
  end
endmodule
