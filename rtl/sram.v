// Single-port synchronous SRAM, 256 x 32-bit, 1-cycle read latency
module sram #(
    parameter DEPTH = 256,
    parameter AW    = 8,
    parameter DW    = 32
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [DW-1:0] wdata,
    output reg  [DW-1:0] rdata
);
    reg [DW-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
        rdata <= mem[addr];
    end
endmodule
