`timescale 1ns/1ps
/* verilator lint_off IMPORTSTAR */
import bias_pkg::*;
/* verilator lint_on IMPORTSTAR */
module bias_brodcast #(
    parameter int BIAS_WIDTH = 32,
    parameter int PE_COLM = 8
)(
  input logic clk,
  input logic reset_n,

  input logic signed [BIAS_WIDTH-1:0] bias_in,
  input logic bias_valid,
  input bias_pkg :: buffer_type_t bias_type,

  input logic [1:0] buffer_select_load,
  input logic [1:0] buffer_select_stream,
  input logic buffer_read,
  input logic buffer_write,


  output logic bias_valid_out,
  output logic signed [BIAS_WIDTH-1:0] bias_out [PE_COLM]
);

logic signed [BIAS_WIDTH-1:0] bias_data;


// Input selection


always_comb begin
    bias_data = '0;

    if(bias_type == BUFFER_SCALLER)
        bias_data = bias_in;
    else if(bias_type == BUFFER_VECTOR)
        bias_data = bias_in;
    else if(bias_type == BUFFER_FULL)
        bias_data = bias_in;
end
logic [2:0] counter;
logic bias_valid_reg;
always_ff @(posedge clk) begin
    if(!reset_n) begin
        counter <= 0;
    end
    else begin

        // start stretching when bias_valid arrives
        if(bias_valid) begin
            bias_valid_reg <= 1;
            counter <= 0;
        end

        // keep valid high for 8 cycles
        else if(bias_valid_reg) begin
            counter <= counter + 1;

            if(counter == 3'd7) begin
                bias_valid_reg <= 0;
                counter <= 0;
            end
        end

    end
end

 logic lock_data;
 assign lock_data = (bias_type==BUFFER_SCALLER);

// Buffer


bias_buffer #(
    .BIAS_WIDTH(BIAS_WIDTH),
    .PE_COLM(PE_COLM)
) bias (
    .clk(clk),
    .reset_n(reset_n),
    .bias_data(bias_data),
    .bias_valid(bias_valid_reg),
    .lock_data(lock_data),

    .bias_out(bias_out),
    .bias_valid_out(bias_valid_out),

    .buffer_select_load(buffer_select_load),
    .buffer_select_stream(buffer_select_stream),
    .buffer_read(buffer_read),
    .buffer_write(buffer_write)
);

endmodule
