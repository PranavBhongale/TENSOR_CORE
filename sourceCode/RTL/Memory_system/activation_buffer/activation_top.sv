`timescale 1ns/1ps
module activation_top #(
    parameter int ACTIVATION_WIDTH = 8,
    parameter int PE_COLS    = 8
)(
    input  logic                         clk,
    input  logic                         reset_n,

    // serial data input
    input  logic signed [ACTIVATION_WIDTH-1:0] activation_data,
    input  logic                         activation_valid,

    // parallel output to PE array
    output logic signed [ACTIVATION_WIDTH-1:0] activation_out [PE_COLS],

    // streaming handshake outputs
    output logic                         streaming_valid,
    output logic                         streaming_start,
    output logic                         streaming_end,
    output logic                         activation_ready

);

logic buffer_read;
logic buffer_write;
logic activation_valid_out ;
logic buffer_select_load;
logic buffer_select_stream;
logic streaming_valid_reg;
//  to assign the signal
assign streaming_valid = streaming_valid_reg && activation_valid_out ;
// CONTROLLER

activation_control #(
    .PE_COLS    (PE_COLS)
) u_activation_controller (

    .clk            (clk),
    .reset_n        (reset_n),

    .activation_valid     (activation_valid),

    .streaming_valid(streaming_valid_reg),
    .streaming_start(streaming_start),
    .streaming_end  (streaming_end),
    .activation_ready   (activation_ready),

    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write)
);

activation_buffer #(
    .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
    .PE_COLM    (PE_COLS)
) activation_buffer (

    .clk            (clk),
    .reset_n        (reset_n),

    // CPU input
    .activation_data        (activation_data),
    .activation_valid     (activation_valid),

    // controller signals
    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write),

    // output to PE
    .activation_valid_out (activation_valid_out),
    .activation_out       (activation_out)
);


endmodule





