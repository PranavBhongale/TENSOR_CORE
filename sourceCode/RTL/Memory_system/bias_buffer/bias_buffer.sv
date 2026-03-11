// THIS IS BUFFER MODULE WHICH
// STORE THE BIAS VALUE FOR 32 BY 64 MATRIX THERE IS ONE BUFFER
// AND FOR VECTOR AND SCALLAR BIAS THERE IS TOW BUFFER FOR ACCELERATING THE COMMON CASE
`timescale 1ns/1ps
//import bias_pkg :: *;
module bias_buffer #(
    parameter int BIAS_WIDTH = 32,
    parameter int PE_COLM= 8
) (
  input logic clk ,
  input logic reset_n,
  // bias input stream
  input logic signed  [BIAS_WIDTH-1:0]bias_data,
  input logic bias_valid,
  input  logic lock_data,
    // bias output to PE columns
  output logic signed [BIAS_WIDTH-1:0]bias_out[PE_COLM],
  output logic bias_valid_out,
  //
  input logic [1:0]buffer_select_load,
  input logic [1:0]buffer_select_stream,
  input logic buffer_read,
  input logic buffer_write
);
logic signed [BIAS_WIDTH-1:0] buffer0 [PE_COLM];
logic signed [BIAS_WIDTH-1:0] buffer1 [PE_COLM];
logic signed [BIAS_WIDTH-1:0] buffer2 [64];   //  this is big buffer which store the full matrix 
                                              // sometimes this matrix is need for transformer

logic [2:0] write_ptr;
logic [5:0] write_ptr_2;

logic [BIAS_WIDTH -1 :0] bias_data_reg;
logic [3:0] counter ;
always_ff@(posedge clk ) begin
  if(!reset_n)begin
    counter <= 0;
    bias_data_reg <= '0;
  end
  if(lock_data)begin
    if(counter == 4'b0001)begin 
     bias_data_reg <= bias_data;
    end  else if(counter != 4'b0000 && counter != 4'b1001 ) begin
        bias_data_reg <= bias_data_reg;
    end  else if(counter == 4'b1001)begin
        counter <= 0;
         bias_data_reg <= bias_data;
    end
    counter <= counter +1 ;
  end else begin
        bias_data_reg <= bias_data;
        counter <= 0;
  end
end








always_ff@(posedge clk )  begin
    if(!reset_n) begin
        write_ptr   <= 0;
        write_ptr_2 <= 0;
    end
    else if(bias_valid && buffer_write) begin

        // write data

        if(buffer_select_load == 0)
            buffer0[write_ptr] <= bias_data_reg;

        else if(buffer_select_load == 1)
            buffer1[write_ptr] <= bias_data_reg;

        else
            buffer2[write_ptr_2] <= bias_data_reg;


        // pointer update


        if(buffer_select_load == 2) begin

            if(write_ptr_2 == 63)
                write_ptr_2 <= 0;
            else
                write_ptr_2 <= write_ptr_2 + 1;

        end
        else begin

            if(write_ptr == 7)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1;

        end

    end
end



// READ LOGIC


int ptr;

always_ff @(posedge clk) begin

    if(!reset_n) begin

        bias_valid_out <= 0;
        ptr <= 0;

        for(int i=0;i<PE_COLM;i++)
            bias_out[i] <= 0;

    end
    else begin

        bias_valid_out <= 0;

        if(buffer_read) begin

            if(buffer_select_stream == 0) begin

                for(int i=0;i<PE_COLM;i++)
                    bias_out[i] <= buffer0[i];

                bias_valid_out <= 1;

            end

            else if(buffer_select_stream == 1) begin

                for(int i=0;i<PE_COLM;i++)
                    bias_out[i] <= buffer1[i];

                bias_valid_out <= 1;

            end

            else begin

                for(int i=0;i<PE_COLM;i++)
                    bias_out[i] <= buffer2[i + PE_COLM*ptr];

                bias_valid_out <= 1;

                if(ptr == PE_COLM-1)
                    ptr <= 0;
                else
                    ptr <= ptr + 1;

            end

        end

    end
end


endmodule
