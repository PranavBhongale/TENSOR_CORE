
`timescale 1ns/1ps
module activation_buffer #(
    parameter int ACTIVATION_WIDTH = 8,
    parameter int PE_COLM= 8
) (
  input logic clk ,
  input logic reset_n,
  // bias input stream
  input logic signed  [ACTIVATION_WIDTH-1:0]activation_data,
  input logic activation_valid,
    // bias output to PE columns
  output logic signed [ACTIVATION_WIDTH-1:0]activation_out[PE_COLM],
  output logic activation_valid_out,
  //  for selection of buffer
  input logic buffer_select_load,
  input logic buffer_select_stream,
  input logic buffer_read,
  input logic buffer_write
);
logic signed [ACTIVATION_WIDTH-1:0] buffer0 [64];
logic signed [ACTIVATION_WIDTH-1:0] buffer1 [64];


 logic [ACTIVATION_WIDTH -1 :0]activation_data_reg;
logic activation_valid_reg ;
always_ff@(posedge clk ) begin
if(!reset_n) begin
   activation_data_reg <= 0;
   activation_valid_reg <= 0;
end else begin
    activation_data_reg <= activation_data;
    activation_valid_reg <= activation_valid;
end
end

logic [5:0] write_ptr;

always_ff@(posedge clk )  begin
    if(!reset_n) begin
        write_ptr <= 0;
    end
    else if(activation_valid_reg && buffer_write) begin

        // write data

        if(buffer_select_load == 0)
            buffer0[write_ptr] <= activation_data_reg;

        else if(buffer_select_load == 1)
            buffer1[write_ptr] <= activation_data_reg;

            if(write_ptr == 63)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1;

        end
    end
// READ LOGIC
int ptr;
always_ff @(posedge clk) begin

    if(!reset_n) begin

        activation_valid_out <= 0;
        ptr <= 0;

        for(int i=0;i<PE_COLM;i++)
            activation_out[i] <= 0;

    end
    else begin

        activation_valid_out <= 0;

        if(buffer_read) begin

            if(buffer_select_stream == 0) begin

                for(int i=0;i<PE_COLM;i++)
                    activation_out[i] <= buffer0[i + PE_COLM*ptr];

                activation_valid_out <= 1;

                if(ptr == PE_COLM)
                    ptr <= 0;
                else
                    ptr <= ptr + 1;

            end

            else if(buffer_select_stream == 1) begin

                for(int i=0;i<PE_COLM;i++)
                    activation_out[i] <= buffer1[i + PE_COLM*ptr];

                activation_valid_out <= 1;

                if(ptr == PE_COLM)
                    ptr <= 0;
                else
                    ptr <= ptr + 1;

            end

        end

    end
end
endmodule
