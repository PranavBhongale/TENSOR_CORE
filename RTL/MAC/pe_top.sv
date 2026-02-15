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
  input logic counter_sync_in,
   // for standerd matrix multiplication we need to add the C value to the psum,
   // so we need to bring it to get heair with the psum, so we can add it in the same
   //cycle and output the final result, but for simplicity we will just output the psum and assume C is added later
  // for addition of C  we need to bring it to get her with the psum, so we can add it in the same cycle and output
  //the final result, but for simplicity we will just output the psum and assume C is added later
  input logic signed [ACC_W-1:0] C_data,
  input logic C_data_valid,
  // we have to flow the data of c to whole systolic array  and we have to give to the next pe and we have to 
  // compute at the last cycle when we have the final psum and the c value, but for simplicity we will just output the psum and assume C is added later
  output logic signed [ACC_W-1:0] C_data_next,
  output logic C_data_valid_next,
  input logic c_lock

);
   logic  C_data_signal;
   logic  counter_sync_reg;
    logic signed [ACC_W-1:0] C_data_reg;
   always_comb begin : c_add_signal_generator
   if(counter_sync_reg && !counter_sync_in) begin
      C_data_signal = 1'b1;
   end else begin
      C_data_signal = 1'b0;
   end
   end
   always_ff @(posedge clk) begin
    if(c_lock) begin
      C_data_reg <= C_data;
    end
  end
  always_ff @(posedge clk) begin : PE_COMPUTE
    if (!reset_n) begin
      acc_data_next <= '0;
      wet_data_next <= '0;
      acc_data_valid_next <= 1'b0;
      wet_data_valid_next <= 1'b0;
      psum <= '0;
      //c_data_signal
      C_data_next <= '0;
      C_data_valid_next <= 1'b0 ;
      counter_sync_reg <= 1'b0;

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
      // Register counter_sync signal
     if(counter_sync_in) begin
        counter_sync_reg <= 1'b1;
      end else begin
        counter_sync_reg <= 1'b0;
      end

      // Accumulate when both are valid
      // to feed the data to next c_data
      // this will feed the data like queue

      if (C_data_valid) begin
        C_data_next <= C_data;
        C_data_valid_next <= 1'b1;
      end else begin
        C_data_valid_next <= 1'b0;
      end
      //
      if (acc_data_valid && wet_data_valid) begin : COMPUTE
        psum <= psum + (acc_data * wet_data);
    end : COMPUTE
  else if(C_data_signal) begin
        psum <= psum + C_data_reg;

      end
      else if(!counter_sync_in) begin
        psum <= 'b0;
      end
    end
    end : PE_COMPUTE
    // always_comb begin : last_addition
    //   if(C_data_signal)begin
    //     psum = psum + C_data ;
    //   end

    // end
endmodule
