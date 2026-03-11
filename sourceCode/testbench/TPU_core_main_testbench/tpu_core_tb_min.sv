`timescale 1ns/1ps

module tpu_core_tb_min;

    // Parameters
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int ROWS   = 8;
    localparam int COLS   = 8;
    localparam int K      = 8;
    localparam int CLK_PERIOD = 10;

    // Clock & Reset
    logic clk    = 0;
    logic reset_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT Ports
    logic signed [DATA_W-1:0] matrix_acc_col  [COLS];
    logic signed [DATA_W-1:0] matrix_wet_row  [ROWS];
    logic                     matrix_acc_valid;
    logic                     matrix_wet_valid;

    logic signed [ACC_W-1:0]  C_data          [COLS];
    logic                     C_data_valid     [COLS];

    logic signed [7:0]        act_data_out     [COLS];
    logic                     valid_out;

    // DUT Instance
    TPU_core_top #(
        .ACC_W (ACC_W),
        .DATA_W(DATA_W),
        .ROWS  (ROWS),
        .COLS  (COLS),
        .K     (K)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .matrix_acc_col  (matrix_acc_col),
        .matrix_wet_row  (matrix_wet_row),
        .matrix_acc_valid(matrix_acc_valid),
        .matrix_wet_valid(matrix_wet_valid),
        .C_data          (C_data),
        .C_data_valid    (C_data_valid),
        .act_data_out    (act_data_out),
        .valid_out       (valid_out)
    );

    // Simple stimulus
    initial begin
        // Initialise
        reset_n          = 0;
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        for (int i = 0; i < COLS; i++) begin
            matrix_acc_col[i] = '0;
            C_data[i]         = '0;
            C_data_valid[i]   = 0;
        end
        for (int i = 0; i < ROWS; i++)
            matrix_wet_row[i] = '0;

        // Reset
        repeat(4) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);

        // Feed one simple transaction (A=1, B=1, C=0)
        for (int k = 0; k < K; k++) begin
            @(posedge clk);
            matrix_acc_valid = 1;
            matrix_wet_valid = 1;
            for (int i = 0; i < COLS; i++) matrix_acc_col[i] = 8'sd1;
            for (int i = 0; i < ROWS; i++) matrix_wet_row[i] = 8'sd1;
            for (int i = 0; i < COLS; i++) C_data_valid[i]   = 0;
        end

        // De-assert
        @(posedge clk);
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;

        // Wait for valid_out
        repeat(200) @(posedge clk);

        $display("Syntax check complete — simulation finished.");
        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("WATCHDOG timeout");
        $finish;
    end

endmodule

