//  this is the top level of activation block, it will contain multiple data lanes and the control logic for 
//the data lanes
`timescale 1ns/1ps
module activation_top #(
    parameter ROWS = 8,
    parameter COLS = 8,
    parameter ACC_D = 32
) (
    input logic clk ,
    input logic reset_n,
    input logic mac_done,
    input logic signed [31:0] mac_data [ROWS][COLS],
    output logic signed [7:0] act_data_out [COLS],
    output logic valid_out ,
    output logic  stream_done
);


        wire  signed [ACC_D-1:0] data_out_from_lane [COLS];
        wire  valid_out_lane;
       // wire stream_done;
    // Instantiate data_lane
    data_lane #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ACC_W(ACC_D)
    ) data_lane (
        .clk(clk),
        .reset_n(reset_n),
        .mac_data(mac_data),
        .mac_done(mac_done),
        .data_out(data_out_from_lane),
        .valid_out(valid_out_lane),
        /* verilator lint_off PINCONNECTEMPTY */
        .stream_done(stream_done)
        /* verilator lint_on PINCONNECTEMPTY */
    );

   // Instantiate look-up table 

//    module Look_Table #(
//     parameter ROWS = 8,
//     parameter COLS = 8
// )(
//     input  logic                          clk,
//     input  logic                          reset_n,
//     input  logic                          valid_in,
//     input  logic signed [7:0]             din   [COLS],
//     output logic signed [7:0]            dout  [COLS],
//     output logic                          valid_out
// );

    Look_Table #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) look_table_inst (
        .clk(clk),
        .reset_n(reset_n),
        .valid_in(clamp_valid_out), // Connect to clamp_unit valid_out
        .din(clamp_data_out), // Connect to clamp_unit dout
        .dout(act_data_out), // Connect to activation_top output
        .valid_out(valid_out) // Connect to activation_top valid_out
    );





    wire signed [7:0] clamp_data_out [COLS];
    wire clamp_valid_out;
    // intiation of shift_unit
    Clamp_unit #(
        .ACC_D(),
        .CLAMP_MIN(-128),
        .CLAMP_MAX(127),
        .CLAMP_SIZE(8),
        .ROWS(ROWS),
        .COLS(COLS)
    ) clamp_unit_inst (
        .clk(clk),
        .reset_n(reset_n),
        .din(shifted_data_out), // Connect to data_lane output
        .valid_in(valid_out_shift), // Connect to data_lane valid_out
        .dout(clamp_data_out), // Connect to gelu_lut input
        .valid_out(clamp_valid_out) // Connect to gelu_lut valid_in
    );


    // shift_unit intiation
   wire signed [ACC_D-1:0] shifted_data_out  [COLS];
   wire valid_out_shift;
  shift_unit #(
        .ACC_D(ACC_D),
        .SHIFT_BITS(3),
        .ROWS(ROWS),
        .COLS(COLS)
    ) shift_unit_inst (
        .clk(clk),
        .reset_n(reset_n),
        .din(data_out_from_lane), // Connect to data_lane output
        .valid_in(valid_out_lane), // Connect to data_lane valid_out
        .dout(shifted_data_out), // Connect to gelu_lut input
        .valid_out(valid_out_shift) // Connect to gelu_lut valid_in
    );



endmodule



