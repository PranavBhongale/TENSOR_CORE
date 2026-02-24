`timescale 1ns/1ps

module TPU_core_top #(
  parameter int ACC_W  = 32 ,
  parameter int DATA_W = 8  ,
  parameter int ROWS   = 8  ,
  parameter int COLS   = 8  ,
  parameter int K      = 8
) (

    input  logic clk ,
    input  logic reset_n,

    // A and B streaming inputs
    input  logic signed [DATA_W-1:0] matrix_acc_col [COLS],
    input  logic signed [DATA_W-1:0] matrix_wet_row [ROWS],
    input  logic matrix_acc_valid,
    input  logic matrix_wet_valid,

    // Bias / C matrix
    input  logic signed [ACC_W-1:0] C_data [COLS],
    input  logic C_data_valid [COLS],

    // Final activation output
    output logic signed [7:0] act_data_out [COLS],
    output logic valid_out
);

    // Internal Signals


    logic signed [ACC_W-1:0] result_matrix [ROWS][COLS];
    logic result_valid;
    logic mac_done;
    logic result_to_activation;
    assign result_to_activation = mac_done && result_valid ;
    // 1️ Systolic Array Instance

    systolic_array_top #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .ROWS(ROWS),
        .COLS(COLS),
        .K(K)
    ) array_top (

        .clk(clk),
        .reset_n(reset_n),
        .done(mac_done),

        .matrix_acc_col(matrix_acc_col),
        .matrix_acc_valid(matrix_acc_valid),

        .matrix_wet_row(matrix_wet_row),
        .matrix_wet_valid(matrix_wet_valid),

        .result_matrix(result_matrix),
        .result_valid(result_valid),

        .C_data(C_data),
        .C_data_valid(C_data_valid)
    );

    // 2️ Activation Block Instance


    activation_top #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ACC_D(ACC_W)
    ) act_top (

        .clk(clk),
        .reset_n(reset_n),
        .mac_done(result_to_activation),
        .mac_data(result_matrix),

        .act_data_out(act_data_out),
        .valid_out(valid_out),
        /* verilator lint_off UNUSEDSIGNAL */
        .stream_done(stream_done)   // optional
    );
logic stream_done ; // this is because when the activation start it after the end it
// gives this signal highe
/* verilator lint_on UNUSEDSIGNAL */

endmodule

