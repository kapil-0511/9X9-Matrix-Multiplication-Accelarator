// Processing Element for systolic matrix multiply.
//
// Data flow:
//   a_in  → accumulate → a_out  (passes A horizontally to right neighbor)
//   b_in  → accumulate → b_out  (passes B vertically to bottom neighbor)
//   c_acc accumulates a_in * b_in every cycle unless clear is asserted.
//
// clear=1 resets c_acc to 0 (does not accumulate that cycle).
// Data still passes through (a_out, b_out) during clear so the pipeline
// does not stall.

module pe #(
    parameter DW = 32,   // operand width (A and B elements)
    parameter AW = 64    // accumulator width
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          clear,   // 1 = reset accumulator, skip multiply
    input  wire [DW-1:0] a_in,   // from left (or left-edge input)
    input  wire [DW-1:0] b_in,   // from top  (or top-edge input)
    output reg  [DW-1:0] a_out,  // pass to right neighbor
    output reg  [DW-1:0] b_out,  // pass to bottom neighbor
    output reg  [AW-1:0] c_acc   // partial product accumulator
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {DW{1'b0}};
            b_out <= {DW{1'b0}};
            c_acc <= {AW{1'b0}};
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            if (clear)
                c_acc <= {AW{1'b0}};
            else
                c_acc <= $signed(c_acc) + $signed(a_in) * $signed(b_in);
        end
    end
endmodule
