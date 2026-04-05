`timescale 1ns/1ps

// ─────────────────────────────────────────────
//  Top-level: output_top
// ─────────────────────────────────────────────
module output_top #(
    parameter int OUTPUT_WIDTH = 8,
    parameter int PE_COLM      = 8
) (
    input  logic clk,
    input  logic reset_n,

    // input from MAC / PE array
    input  logic signed [OUTPUT_WIDTH-1:0] output_data_streaming [PE_COLM],
    input  logic                           output_data_valid_in,

    // output to downstream
    output logic signed [OUTPUT_WIDTH-1:0] output_data_len,
    output logic                           output_data_len_valid,
    output logic                           output_ready
);

    // ── internal wires ──────────────────────────────────────
    logic buffer_select_load;
    logic buffer_select_stream;
    logic buffer_read;
    logic buffer_write;

    logic streaming_valid_reg;
    logic output_data_len_valid_reg;
    assign  output_data_len_valid = streaming_valid_reg && output_data_len_valid_reg;
    assign  streaming_valid = streaming_valid_reg && output_data_len_valid_reg;
/* verilator lint_off UNUSEDSIGNAL */
    logic streaming_valid;
/* verilator lint_on UNUSEDSIGNAL */
    // ── output_control instantiation ────────────────────────
    output_control #(
        .PE_COLM(PE_COLM)
    ) u_output_control (

        .clk                  (clk),
        .reset_n              (reset_n),
        .output_data_valid_in    (output_data_valid_in),
        .output_ready         (output_ready),
        .buffer_select_load  (buffer_select_load),
        .buffer_select_stream(buffer_select_stream),
        .buffer_read         (buffer_read),
        .buffer_write        (buffer_write),
        .streaming_valid     (streaming_valid_reg)
    );

    // ── output_buffer instantiation ─────────────────────────
    output_buffer #(
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PE_COLM     (PE_COLM)
    ) u_output_buffer (
        .clk                 (clk),
        .reset_n             (reset_n),

        // data path: PE columns → buffer → output
        .output_data_in           (output_data_streaming),
        .output_valid_in     (output_data_valid_in),
        .output_data_out         (output_data_len),       // buffer stream → top output
        .output_valid_out        (output_data_len_valid_reg),

        // control path
        .buffer_select_load  (buffer_select_load),
        .buffer_select_stream(buffer_select_stream),
        .buffer_read         (buffer_read),
        .buffer_write        (buffer_write)
    );

endmodule

