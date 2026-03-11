`timescale 1ns/1ps

module activation_tb_simple;

    // =========================================================
    // Parameters
    // =========================================================
    parameter ROWS       = 8;
    parameter COLS       = 8;
    parameter ACC_W      = 32;
    parameter CLK_PERIOD = 10;

    // =========================================================
    // Signals
    // =========================================================
    logic                    clk;
    logic                    reset_n;
    logic                    mac_done;
    logic signed [ACC_W-1:0] mac_data [ROWS][COLS];

    logic signed [7:0]       act_data_out [COLS];
    logic                    valid_out;

    // =========================================================
    // DUT
    // =========================================================
    activation_top #(
        .ROWS  (ROWS),
        .COLS  (COLS),
        .ACC_D (ACC_W)
    ) dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .mac_done      (mac_done),
        .mac_data      (mac_data),
        .act_data_out (act_data_out),
        .valid_out     (valid_out)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // VCD
    // =========================================================
    initial begin
        $dumpfile("tb_activation_top.vcd");
        $dumpvars(0, tb_activation_top);
    end

    // =========================================================
    // Watchdog
    // =========================================================
    initial begin
        #(CLK_PERIOD * 2000);
        $display("WATCHDOG: simulation timeout");
        $finish;
    end

    // =========================================================
    // Print every valid_out beat
    // =========================================================
    int beat_num;
    initial beat_num = 0;

    always @(posedge clk) begin
        if (!reset_n) begin
            beat_num <= 0;
        end else if (valid_out) begin
            $write("  beat[%0d]:", beat_num);
            for (int r = 0; r < ROWS; r++)
                $write(" %4d", act_data_out[r]);
            $write("\n");
            beat_num <= beat_num + 1;
        end
    end

    // =========================================================
    // Main stimulus
    // =========================================================
    initial begin

        // --- initialise ---
        reset_n  = 0;
        mac_done = 0;
        beat_num = 0;
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = '0;

        // --- reset for 4 cycles ---
        repeat(4) @(posedge clk);
        #1; reset_n = 1;
        repeat(2) @(posedge clk);

        // ======================================================
        // TEST 1: All zeros
        // ======================================================
        $display("\n--- TEST 1: All zeros ---");
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = 0;

        #1; mac_done = 1;
        @(posedge clk); #1; mac_done = 0;

        repeat(25) @(posedge clk); // wait for 8 output beats

        // ======================================================
        // TEST 2: Sequential values scaled by 8
        //   after >>3 → values 0..63 reaching GELU
        // ======================================================
        $display("\n--- TEST 2: Sequential (0..63 after shift) ---");
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = (r * COLS + c) * 8;

        #1; mac_done = 1;
        @(posedge clk); #1; mac_done = 0;

        repeat(25) @(posedge clk);

        // ======================================================
        // TEST 3: Large positive → clamp to +127
        // ======================================================
        $display("\n--- TEST 3: Large positive (clamp +127) ---");
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = 32'sd100000;

        #1; mac_done = 1;
        @(posedge clk); #1; mac_done = 0;

        repeat(25) @(posedge clk);

        // ======================================================
        // TEST 4: Large negative → clamp to -128
        // ======================================================
        $display("\n--- TEST 4: Large negative (clamp -128) ---");
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = -32'sd100000;

        #1; mac_done = 1;
        @(posedge clk); #1; mac_done = 0;

        repeat(25) @(posedge clk);

        // ======================================================
        // TEST 5: Mixed positive / negative
        // ======================================================
        $display("\n--- TEST 5: Mixed pos/neg ---");
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = ((r + c) % 2 == 0) ? 32'sd512 : -32'sd512;

        #1; mac_done = 1;
        @(posedge clk); #1; mac_done = 0;

        repeat(25) @(posedge clk);

        // ======================================================
        // Done
        // ======================================================
        $display("\n--- All tests complete ---");
        $finish;
    end

endmodule
