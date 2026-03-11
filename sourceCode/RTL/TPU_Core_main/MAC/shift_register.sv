module shift_register #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 1   // minimum 1
)(
  input  logic              clk,
  input  logic              reset_n,
  input  logic [WIDTH-1:0]  din,
  input  logic              valid_in,
  output logic [WIDTH-1:0]  dout,
  output logic              valid_out
);

  logic [WIDTH-1:0] data_pipe  [DEPTH];
  logic              valid_pipe [DEPTH];

  always_ff @(posedge clk) begin
    if (!reset_n) begin
      for (int i = 0; i < DEPTH; i++) begin
        data_pipe[i]  <= '0;
        valid_pipe[i] <= 1'b0;
      end
    end else begin
      data_pipe[0]  <= din;
      valid_pipe[0] <= valid_in;
      for (int i = 1; i < DEPTH; i++) begin
        data_pipe[i]  <= data_pipe[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign dout      = data_pipe[DEPTH-1];
  assign valid_out = valid_pipe[DEPTH-1];

endmodule
