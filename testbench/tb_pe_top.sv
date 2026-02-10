//====================================================
// File: tb_pe_top.sv
// Description: Testbench for systolic pe_top
//====================================================
`timescale 1ns/1ps

module tb_pe_top;

  // Parameters
  localparam int DATA_W = 8;
  localparam int ACC_W  = 32;

  // DUT signals
  logic clk;
  logic rst_n;

  logic signed [DATA_W-1:0] act;
  logic signed [DATA_W-1:0] wgt;

  logic acc_en;
  logic acc_clr;

  logic signed [DATA_W-1:0] act_out;
  logic signed [DATA_W-1:0] wgt_out;
  logic signed [ACC_W-1:0]  psum;

  int expected_psum;

  // -------------------------------------------------
  // Instantiate DUT
  // -------------------------------------------------
  pe_top #(
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
  ) dut (
    .clk     (clk),
    .rst_n   (rst_n),
    .act     (act),
    .wgt     (wgt),
    .acc_en  (acc_en),
    .acc_clr (acc_clr),
    .act_out (act_out),
    .wgt_out (wgt_out),
    .psum    (psum)
  );

  // -------------------------------------------------
  // Clock generation (10ns period)
  // -------------------------------------------------
  always #5 clk = ~clk;

  // -------------------------------------------------
  // Test sequence
  // -------------------------------------------------
  initial begin
    // Initialize
    clk     = 0;
    rst_n   = 0;
    act     = 0;
    wgt     = 0;
    acc_en  = 0;
    acc_clr = 0;
    expected_psum = 0;

    // Apply reset
    #20;
    rst_n = 1;

    // Clear accumulator
    @(posedge clk);
    acc_clr = 1;
    acc_en  = 0;

    @(posedge clk);
    acc_clr = 0;

    // ---------------------------------------------
    // SYSTOLIC-LIKE DATA FEED
    // ---------------------------------------------
    acc_en = 1;

    repeat (5) begin
      @(posedge clk);
      /* verilator lint_off WIDTHTRUNC */
      act = $urandom_range(1, 10);
      wgt = $urandom_range(1, 10);
      /* verilator lint_on WIDTHTRUNC */
      expected_psum += act * wgt;

      $display("act=%0d wgt=%0d | act_out=%0d wgt_out=%0d | psum=%0d",
               act, wgt, act_out, wgt_out, psum);
    end

    // Stop accumulation
    @(posedge clk);
    acc_en = 0;

    #1;
    $display("-----------------------------------");
    $display("Expected psum = %0d", expected_psum);
    $display("DUT psum      = %0d", psum);

    if (psum == expected_psum)
      $display("✅ TEST PASSED");
    else
      $display("❌ TEST FAILED");

    #20;
    $finish;
  end

  // -------------------------------------------------
  // Waveform dump
  // -------------------------------------------------
  initial begin
    $dumpfile("pe_wave.vcd");
    $dumpvars(0, tb_pe_top);
  end

endmodule
