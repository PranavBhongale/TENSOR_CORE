`timescale 1ns/1ps
module weight_top #(
    parameter int WEIGHT_WIDTH = 8,
    parameter int PE_COLS    = 8
)(
    input  logic                         clk,
    input  logic                         reset_n,

    // serial data input
    input  logic signed [WEIGHT_WIDTH-1:0] weight_data,
    input  logic                         weight_valid,

    // parallel output to PE array
    output logic signed [WEIGHT_WIDTH-1:0] weight_out [PE_COLS],

    // streaming handshake outputs
    output logic                         streaming_valid,
    output logic                         streaming_start,
    output logic                         streaming_end,
    output logic                         weight_ready

);

logic buffer_read;
logic buffer_write;
logic weight_valid_out ;
logic buffer_select_load;
logic buffer_select_stream;
logic streaming_valid_reg;
assign streaming_valid = streaming_valid_reg && weight_valid_out ;
// CONTROLLER

weight_control #(
    .PE_COLS    (PE_COLS)
) u_bias_controller (

    .clk            (clk),
    .reset_n        (reset_n),

    .weight_valid     (weight_valid),

    .streaming_valid(streaming_valid_reg),
    .streaming_start(streaming_start),
    .streaming_end  (streaming_end),
    .weight_ready   (weight_ready),

    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write)
);

weight_buffer #(
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .PE_COLM    (PE_COLS)
) u_bias_broadcast (

    .clk            (clk),
    .reset_n        (reset_n),

    // CPU input
    .weight_data        (weight_data),
    .weight_valid     (weight_valid),

    // controller signals
    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write),

    // output to PE
    .weight_valid_out (weight_valid_out),
    .weight_out       (weight_out)
);



endmodule



