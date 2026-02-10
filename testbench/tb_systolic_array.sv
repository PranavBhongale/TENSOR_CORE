`timescale 1ns/1ps

module tb_systolic_array;

    // Parameters
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int ROWS   = 4;
    localparam int COLS   = 4;
    localparam int K      = 4;

    // Clock period
    localparam int CLK_PERIOD = 10;

    // Clock & reset
    logic clk;
    logic reset_n;

    // DUT I/O
    logic done;
    logic signed [DATA_W-1:0] matrix_acc_col  [COLS];
    logic                     matrix_acc_valid;
    logic signed [DATA_W-1:0] matrix_wet_row  [ROWS];
    logic                     matrix_wet_valid;
    logic signed [ACC_W-1:0]  result_matrix   [ROWS][COLS];
    logic                     result_valid;

    // Test matrices  <-- EDIT THESE VALUES TO CHANGE YOUR TEST
    logic signed [DATA_W-1:0] test_matrix_a [ROWS][K];
    logic signed [DATA_W-1:0] test_matrix_b [K][COLS];
    logic signed [ACC_W-1:0]  expected_result [ROWS][COLS];

    //========================================================================
    // Clock Generation
    //========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //========================================================================
    // DUT Instantiation
    //========================================================================
    systolic_array_top #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W),
        .ROWS  (ROWS),
        .COLS  (COLS)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .done             (done),
        .matrix_acc_col   (matrix_acc_col),
        .matrix_acc_valid (matrix_acc_valid),
        .matrix_wet_row   (matrix_wet_row),
        .matrix_wet_valid (matrix_wet_valid),
        .result_matrix    (result_matrix),
        .result_valid     (result_valid)
    );

    //========================================================================
    // Tasks
    //========================================================================

    // Task: Initialize signals
    task automatic init_signals();
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        for (int i = 0; i < COLS; i++) matrix_acc_col[i] = 0;
        for (int i = 0; i < ROWS; i++) matrix_wet_row[i] = 0;
    endtask

    // Task: Apply reset
    task automatic apply_reset();
        $display("[%0t] Applying reset...", $time);
        reset_n = 0;
        init_signals();
        repeat(3) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        $display("[%0t] Reset released", $time);
    endtask

    // Function: Software reference model (golden result)
    function automatic void calculate_expected_result(
        input  logic signed [DATA_W-1:0] mat_a    [ROWS][K],
        input  logic signed [DATA_W-1:0] mat_b    [K][COLS],
        output logic signed [ACC_W-1:0]  expected [ROWS][COLS]
    );
        for (int i = 0; i < ROWS; i++) begin
            for (int j = 0; j < COLS; j++) begin
                expected[i][j] = 0;
                for (int k = 0; k < K; k++) begin
                    expected[i][j] += mat_a[i][k] * mat_b[k][j];
                end
            end
        end
    endfunction

    // Task: Feed matrices to DUT (column-by-column)
    task automatic feed_matrices(
        input logic signed [DATA_W-1:0] mat_a [ROWS][K],
        input logic signed [DATA_W-1:0] mat_b [K][COLS]
    );
        $display("[%0t] Feeding matrices to DUT...", $time);
        for (int k = 0; k < K; k++) begin
            @(posedge clk);
            matrix_acc_valid = 1;
            matrix_wet_valid = 1;
            for (int i = 0; i < ROWS; i++) matrix_acc_col[i] = mat_a[i][k];
            for (int j = 0; j < COLS; j++) matrix_wet_row[j] = mat_b[k][j];
        end
        @(posedge clk);
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        $display("[%0t] Finished feeding matrices", $time);
    endtask

    // Task: Wait for done + result_valid
    task automatic wait_for_completion(input int timeout_cycles = 1000);
        $display("[%0t] Waiting for done signal...", $time);
        fork
            begin
                wait(done == 1);
                $display("[%0t] Done signal asserted", $time);
            end
            begin
                repeat(timeout_cycles) @(posedge clk);
                $display("[%0t] ERROR: Timeout! Done never asserted.", $time);
            end
        join_any
        disable fork;
        wait(result_valid == 1);
        $display("[%0t] Result valid asserted", $time);
    endtask

    // Task: Display matrix A
    task automatic display_matrix_a(
        input string name,
        input logic signed [DATA_W-1:0] mat [ROWS][K]
    );
        $display("\n%s [%0dx%0d]:", name, ROWS, K);
        for (int i = 0; i < ROWS; i++) begin
            $write("  | ");
            for (int j = 0; j < K; j++) $write("%4d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Display matrix B
    task automatic display_matrix_b(
        input string name,
        input logic signed [DATA_W-1:0] mat [K][COLS]
    );
        $display("\n%s [%0dx%0d]:", name, K, COLS);
        for (int i = 0; i < K; i++) begin
            $write("  | ");
            for (int j = 0; j < COLS; j++) $write("%4d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Display result matrix (ACC_W wide)
    task automatic display_result_matrix(
        input string name,
        input logic signed [ACC_W-1:0] mat [ROWS][COLS]
    );
        $display("\n%s [%0dx%0d]:", name, ROWS, COLS);
        for (int i = 0; i < ROWS; i++) begin
            $write("  | ");
            for (int j = 0; j < COLS; j++) $write("%6d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Check result vs expected
    task automatic check_results(
        input logic signed [ACC_W-1:0] expected [ROWS][COLS]
    );
        bit   passed    = 1;
        int   mismatches = 0;

        $display("\n----------------------------------------");
        $display("  Checking Result vs Expected");
        $display("----------------------------------------");

        for (int i = 0; i < ROWS; i++) begin
            for (int j = 0; j < COLS; j++) begin
                if (result_matrix[i][j] !== expected[i][j]) begin
                    $display("  MISMATCH [%0d][%0d]: Expected = %0d,  Got = %0d",
                             i, j, expected[i][j], result_matrix[i][j]);
                    passed = 0;
                    mismatches++;
                end
            end
        end

        display_result_matrix("Expected Result", expected);
        display_result_matrix("DUT Result     ", result_matrix);

        $display("\n----------------------------------------");
        if (passed)
            $display("  RESULT:  PASS ✓");
        else
            $display("  RESULT:  FAIL ✗  (%0d mismatches)", mismatches);
        $display("----------------------------------------\n");
    endtask

    //========================================================================
    // MAIN TEST  —  Edit matrix values here
    //========================================================================
    initial begin

        // ----------------------------------------------------------------
        //  >>>  SET YOUR MATRIX VALUES HERE  <<<
        //
        //  Matrix A  [ROWS x K]   (Activation matrix)
        //
        //       col0  col1
        // row0 [  1    2  ]
        // row1 [  3    4  ]
        //
        test_matrix_a[0][0] =  1;   test_matrix_a[0][1] =  2;
        test_matrix_a[1][0] =  3;   test_matrix_a[1][1] =  4;

        //  Matrix B  [K x COLS]   (Weight matrix)
        //
        //       col0  col1
        // row0 [  5    6  ]
        // row1 [  7    8  ]
        //
        test_matrix_b[0][0] =  5;   test_matrix_b[0][1] =  6;
        test_matrix_b[1][0] =  7;   test_matrix_b[1][1] =  8;
        // ----------------------------------------------------------------

        // Initialize and reset
        clk     = 0;
        reset_n = 0;
        init_signals();
        apply_reset();

        // Print header
        $display("╔══════════════════════════════════════╗");
        $display("║        SYSTOLIC ARRAY - SINGLE TEST  ║");
        $display("╚══════════════════════════════════════╝");

        // Show input matrices
        display_matrix_a("Matrix A (Activations)", test_matrix_a);
        display_matrix_b("Matrix B (Weights)",     test_matrix_b);

        // Compute software golden result
        calculate_expected_result(test_matrix_a, test_matrix_b, expected_result);

        // Drive DUT
        feed_matrices(test_matrix_a, test_matrix_b);

        // Wait for DUT to finish
        wait_for_completion();

        // Compare and report
        check_results(expected_result);

        repeat(10) @(posedge clk);
        $finish;
    end

    //========================================================================
    // Waveform Dump
    //========================================================================
    initial begin
        $dumpfile("sa.vcd");
        $dumpvars(0, tb_systolic_array);
    end

    //========================================================================
    // Simulation Watchdog
    //========================================================================
    initial begin
        #500000;
        $display("ERROR: Simulation watchdog timeout!");
        $finish;
    end

endmodule
