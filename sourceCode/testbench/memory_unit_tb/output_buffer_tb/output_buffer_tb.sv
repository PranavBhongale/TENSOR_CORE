`timescale 1ns/1ps

module output_buffer_tb;

    // ── Parameters ───────────────────────────────────────────
    parameter int OUTPUT_WIDTH = 8;
    parameter int PE_COLM      = 8;
    parameter int TIMEOUT_CYC  = 20000;

    // ── DUT Signals ──────────────────────────────────────────
    logic clk;
    logic reset_n;

    logic signed [OUTPUT_WIDTH-1:0] output_data_streaming [PE_COLM];
    logic                           output_data_valid_in;

    logic signed [OUTPUT_WIDTH-1:0] output_data_len;
    logic                           output_data_len_valid;
    logic                           output_ready;

    // ── Report Variables ─────────────────────────────────────
    integer report_file;
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // ── DUT Instantiation ────────────────────────────────────
    output_top #(
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PE_COLM     (PE_COLM)
    ) dut (
        .clk                   (clk),
        .reset_n               (reset_n),
        .output_data_streaming (output_data_streaming),
        .output_data_valid_in     (output_data_valid_in),
        .output_data_len       (output_data_len),
        .output_data_len_valid (output_data_len_valid),
        .output_ready          (output_ready)
    );

    // ── Clock ─────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Watchdog ─────────────────────────────────────────────
    initial begin
        repeat(TIMEOUT_CYC) @(posedge clk);
        $display("[%0t] ERROR : TIMEOUT", $time);
        $finish;
    end

    // ── Task : Send Data ─────────────────────────────────────
    task automatic send_when_ready(input int base);
    begin
        @(posedge clk iff output_ready);

        for (int i = 0; i < PE_COLM; i++) begin
            @(posedge clk);
            output_data_valid_in = 1;

            for(int j = 0 ; j < PE_COLM ; j++)
                output_data_streaming[j] = 8'( base +PE_COLM*i + j);
        end

        @(posedge clk);
        output_data_valid_in = 0;

        for(int j = 0 ; j < PE_COLM ; j++)
            output_data_streaming[j] = 0;
    end
    endtask

    // ── Checker ──────────────────────────────────────────────
    task automatic check_output(input int expected_len);
    begin
        total_tests++;

        wait(output_data_len_valid);

        if(8'(output_data_len) == 8'(expected_len)) begin
            passed_tests++;
            $display("[%0t] TEST PASS : length=%0d",
                     $time, output_data_len);
            $fdisplay(report_file,
                     "[%0t] TEST PASS : length=%0d",
                     $time, output_data_len);
        end
        else begin
            failed_tests++;
            $display("[%0t] TEST FAIL : expected=%0d got=%0d",
                     $time, expected_len, output_data_len);
            $fdisplay(report_file,
                     "[%0t] TEST FAIL : expected=%0d got=%0d",
                     $time, expected_len, output_data_len);
        end
    end
    endtask

    // ── Stimulus ─────────────────────────────────────────────
    initial begin

        report_file = $fopen("simulation_report.txt","w");

        reset_n           = 0;
        output_data_valid_in = 0;

        foreach(output_data_streaming[i])
            output_data_streaming[i] = 0;

        repeat(4) @(posedge clk);
        reset_n = 1;

        @(posedge clk);

        // TEST 1
        send_when_ready(1);
        send_when_ready(10);
         send_when_ready(100);

        repeat(5) @(posedge clk);

        // ── Final Report ──────────────────────────────────────
        $display("\n-----------------------------");
        $display("SIMULATION REPORT");
        $display("-----------------------------");
        $display("TOTAL TESTS  : %0d", total_tests);
        $display("PASSED TESTS : %0d", passed_tests);
        $display("FAILED TESTS : %0d", failed_tests);

        $fdisplay(report_file,"\n-----------------------------");
        $fdisplay(report_file,"SIMULATION REPORT");
        $fdisplay(report_file,"TOTAL TESTS  : %0d", total_tests);
        $fdisplay(report_file,"PASSED TESTS : %0d", passed_tests);
        $fdisplay(report_file,"FAILED TESTS : %0d", failed_tests);

        $fclose(report_file);
       #2200;
       $finish;
    end

    // ── Monitor ──────────────────────────────────────────────
    always @(posedge clk) begin
        if (output_data_len_valid)
            $display("[%0t] MONITOR len=%0d ready=%b",
                     $time, output_data_len, output_ready);
    end

    // ── Wave Dump ────────────────────────────────────────────
    initial begin
        $dumpfile("output_buffer_tb.vcd");
        $dumpvars(0, output_buffer_tb);
    end

endmodule
