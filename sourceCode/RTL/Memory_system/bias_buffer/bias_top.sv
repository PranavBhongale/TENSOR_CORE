`timescale 1ns/1ps
`include "bias_pkg.svh"
//import bias_pkg :: *;
module bias_top #(
    parameter int BIAS_WIDTH = 32,
    parameter int PE_COLS    = 8
)(
    input  logic                         clk,
    input  logic                         reset_n,

    // serial data input
    input  logic signed [BIAS_WIDTH-1:0] bias_data,
    input  logic                         bias_valid,
    input bias_pkg ::  buffer_type_t                 bias_type,

    // parallel output to PE array
    output logic signed [BIAS_WIDTH-1:0] bias_out [PE_COLS],

    // streaming handshake outputs
    output logic                         streaming_valid,
    output logic                         streaming_start,
    output logic                         streaming_end,
    output logic                         bias_ready,
    output logic                         bias_ready_full_matrix

);

// INTERNAL SIGNALS


assign streaming_valid = streaming_valid_reg && bias_valid_out ;
logic streaming_valid_reg;

logic buffer_read;
logic buffer_write;

logic bias_valid_out;
logic [1:0] buffer_select_load;
logic [1:0] buffer_select_stream;

// CONTROLLER

bias_controller #(
  //  .BIAS_WIDTH (BIAS_WIDTH),
    .PE_COLS    (PE_COLS)
) u_bias_controller (

    .clk            (clk),
    .reset_n        (reset_n),

    .bias_valid     (bias_valid),
    .bias_type      (bias_type),

    .streaming_valid(streaming_valid_reg),
    .streaming_start(streaming_start),
    .streaming_end  (streaming_end),
    .bias_ready     (bias_ready),
    .bias_ready_full_matrix(bias_ready_full_matrix),

    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write)
);


// BROADCAST UNIT


bias_brodcast #(
    .BIAS_WIDTH (BIAS_WIDTH),
    .PE_COLM    (PE_COLS)
) u_bias_broadcast (

    .clk            (clk),
    .reset_n        (reset_n),

    // CPU input
    .bias_in        (bias_data),
    .bias_valid     (bias_valid),
    .bias_type      (bias_type),

    // controller signals
    .buffer_select_load  (buffer_select_load),
    .buffer_select_stream  (buffer_select_stream),
    .buffer_read    (buffer_read),
    .buffer_write   (buffer_write),

    // output to PE
    .bias_valid_out (bias_valid_out),
    .bias_out       (bias_out)
);

endmodule
