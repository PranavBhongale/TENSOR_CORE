
`timescale 1ns/1ps
module output_buffer #(
    parameter int OUTPUT_WIDTH = 8,
    parameter int PE_COLM= 8
) (
  input logic clk ,
  input logic reset_n,
  // bias input stream
  output logic signed  [OUTPUT_WIDTH-1:0]output_data_out,
  output logic output_valid_out,
    // bias output to PE columns
  input logic signed [OUTPUT_WIDTH-1:0]output_data_in[PE_COLM],
  input logic output_valid_in,
  //  for selection of buffer
  input logic buffer_select_load,
  input logic buffer_select_stream,
  input logic buffer_read,
  input logic buffer_write
);

logic signed [OUTPUT_WIDTH-1:0] buffer0 [64];
logic signed [OUTPUT_WIDTH-1:0] buffer1 [64];

//  if  we need register input
logic [ OUTPUT_WIDTH-1 :0]output_data_reg[PE_COLM];
logic output_valid_reg ;
always_ff@(posedge clk ) begin
if(!reset_n) begin
    for(int i = 0 ; i < PE_COLM ; i++)
       output_data_reg[i] <= 0;
   output_valid_reg <= 0;
end else begin
    output_data_reg <= output_data_in;
    output_valid_reg <= output_valid_in;
end
end

//  this is for write the data

int ptr;
always_ff@(posedge clk )begin
 if(!reset_n)begin
 ptr <= 0;
 end
 else begin
    if(output_valid_reg && buffer_write)begin
  if(buffer_select_load == 0) begin
     for(int i = 0 ; i< PE_COLM ; i++)
        buffer0[ptr*PE_COLM  + i ] <= output_data_reg[i];
  end
  else  if(buffer_select_load == 1) begin
     for(int i = 0 ; i< PE_COLM ; i++)
        buffer1[ptr*PE_COLM  + i ] <= output_data_reg[i];
  end
    ptr <= (ptr == (64/PE_COLM -1)) ? 0 : ptr + 1;
end else begin
    ptr <= 0;
end
end
end

//  this is for read the data;
logic [5:0] ptr_read;
always_ff@(posedge clk ) begin
if(!reset_n)begin
output_data_out <= 0;
output_valid_out <= 0;
ptr_read <= 0;
end else begin
if(buffer_read)begin
    if(buffer_select_stream == 0 )
        output_data_out <= buffer0[ptr_read];
    if(buffer_select_stream == 1)
        output_data_out <= buffer1[ptr_read];


    output_valid_out <= 1;
    ptr_read <= ptr_read + 1;
    if(ptr_read == 63)begin
      ptr_read <= 0;
    end
end else begin
    ptr_read <= 0 ;
    output_valid_out <= 0;
end
end
end


endmodule
