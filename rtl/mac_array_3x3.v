// 3×3 systolic MAC array — weight-stationary, diagonal wavefront.
//
// A flows left→right, B flows top→bottom. Row i of A and col j of B are
// skewed so A[i][k] and B[k][j] meet at PE[i][j] at the same cycle.
//
//   b_top[0]   b_top[1]   b_top[2]
//      ↓          ↓          ↓
//  a_left[0]→[PE00]→[PE01]→[PE02]
//  a_left[1]→[PE10]→[PE11]→[PE12]
//  a_left[2]→[PE20]→[PE21]→[PE22]
//
// Timeline per tile: cyc=1 clear, cyc=2..8 data (7 cycles), done at cyc=9.
// a_buf[(i*3+k)*DW +: DW] = A[i][k],  b_buf[(k*3+j)*DW +: DW] = B[k][j]

module mac_array_3x3 #(
    parameter DW = 32,
    parameter AW = 64
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,
    output reg             done,
    input  wire [9*DW-1:0] a_buf,   // A tile: a_buf[(i*3+k)*DW +: DW] = A[i][k]
    input  wire [9*DW-1:0] b_buf,   // B tile: b_buf[(k*3+j)*DW +: DW] = B[k][j]
    output wire [9*AW-1:0] c_out    // C partial: c_out[(i*3+j)*AW +: AW] = C[i][j]
);

    // 0=idle, 1=clear, 2..8=data
    reg [3:0] cyc;
    reg       running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc     <= 4'd0;
            running <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                running <= 1'b1;
                cyc     <= 4'd1;
            end else if (running) begin
                if (cyc == 4'd8) begin
                    running <= 1'b0;
                    cyc     <= 4'd0;
                    done    <= 1'b1;
                end else begin
                    cyc <= cyc + 4'd1;
                end
            end
        end
    end

    wire pe_clear = (cyc == 4'd1);

    // Left-edge A: row i injected at cyc=k+i+2
    reg [DW-1:0] a_left_0, a_left_1, a_left_2;

    always @(*) begin
        case (cyc)
            4'd2: a_left_0 = a_buf[ 0*DW +: DW];   // A[0][0]
            4'd3: a_left_0 = a_buf[ 1*DW +: DW];   // A[0][1]
            4'd4: a_left_0 = a_buf[ 2*DW +: DW];   // A[0][2]
            default: a_left_0 = {DW{1'b0}};
        endcase
    end

    always @(*) begin
        case (cyc)
            4'd3: a_left_1 = a_buf[ 3*DW +: DW];   // A[1][0]
            4'd4: a_left_1 = a_buf[ 4*DW +: DW];   // A[1][1]
            4'd5: a_left_1 = a_buf[ 5*DW +: DW];   // A[1][2]
            default: a_left_1 = {DW{1'b0}};
        endcase
    end

    always @(*) begin
        case (cyc)
            4'd4: a_left_2 = a_buf[ 6*DW +: DW];   // A[2][0]
            4'd5: a_left_2 = a_buf[ 7*DW +: DW];   // A[2][1]
            4'd6: a_left_2 = a_buf[ 8*DW +: DW];   // A[2][2]
            default: a_left_2 = {DW{1'b0}};
        endcase
    end

    // Top-edge B: col j injected at cyc=k+j+2
    reg [DW-1:0] b_top_0, b_top_1, b_top_2;

    always @(*) begin
        case (cyc)
            4'd2: b_top_0 = b_buf[ 0*DW +: DW];    // B[0][0]
            4'd3: b_top_0 = b_buf[ 3*DW +: DW];    // B[1][0]
            4'd4: b_top_0 = b_buf[ 6*DW +: DW];    // B[2][0]
            default: b_top_0 = {DW{1'b0}};
        endcase
    end

    always @(*) begin
        case (cyc)
            4'd3: b_top_1 = b_buf[ 1*DW +: DW];    // B[0][1]
            4'd4: b_top_1 = b_buf[ 4*DW +: DW];    // B[1][1]
            4'd5: b_top_1 = b_buf[ 7*DW +: DW];    // B[2][1]
            default: b_top_1 = {DW{1'b0}};
        endcase
    end

    always @(*) begin
        case (cyc)
            4'd4: b_top_2 = b_buf[ 2*DW +: DW];    // B[0][2]
            4'd5: b_top_2 = b_buf[ 5*DW +: DW];    // B[1][2]
            4'd6: b_top_2 = b_buf[ 8*DW +: DW];    // B[2][2]
            default: b_top_2 = {DW{1'b0}};
        endcase
    end

    // a_h[row*4+col]: col=0 is left-edge input, col=1..3 are PE a_out chain
    // b_v[row*3+col]: row=0 is top-edge input,  row=1..3 are PE b_out chain
    wire [DW-1:0] a_h  [0:11];
    wire [DW-1:0] b_v  [0:11];
    wire [AW-1:0] pe_c [0:8];

    assign a_h[0] = a_left_0;   // row 0 left edge
    assign a_h[4] = a_left_1;   // row 1 left edge
    assign a_h[8] = a_left_2;   // row 2 left edge

    assign b_v[0] = b_top_0;    // col 0 top edge
    assign b_v[1] = b_top_1;    // col 1 top edge
    assign b_v[2] = b_top_2;    // col 2 top edge

    // Row 0
    pe #(.DW(DW), .AW(AW)) u_pe_00 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 0]), .b_in(b_v[0]), .a_out(a_h[ 1]), .b_out(b_v[3]), .c_acc(pe_c[0]));
    pe #(.DW(DW), .AW(AW)) u_pe_01 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 1]), .b_in(b_v[1]), .a_out(a_h[ 2]), .b_out(b_v[4]), .c_acc(pe_c[1]));
    pe #(.DW(DW), .AW(AW)) u_pe_02 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 2]), .b_in(b_v[2]), .a_out(a_h[ 3]), .b_out(b_v[5]), .c_acc(pe_c[2]));

    // Row 1
    pe #(.DW(DW), .AW(AW)) u_pe_10 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 4]), .b_in(b_v[3]), .a_out(a_h[ 5]), .b_out(b_v[6]), .c_acc(pe_c[3]));
    pe #(.DW(DW), .AW(AW)) u_pe_11 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 5]), .b_in(b_v[4]), .a_out(a_h[ 6]), .b_out(b_v[7]), .c_acc(pe_c[4]));
    pe #(.DW(DW), .AW(AW)) u_pe_12 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 6]), .b_in(b_v[5]), .a_out(a_h[ 7]), .b_out(b_v[8]), .c_acc(pe_c[5]));

    // Row 2
    pe #(.DW(DW), .AW(AW)) u_pe_20 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 8]), .b_in(b_v[6]), .a_out(a_h[ 9]), .b_out(b_v[ 9]), .c_acc(pe_c[6]));
    pe #(.DW(DW), .AW(AW)) u_pe_21 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[ 9]), .b_in(b_v[7]), .a_out(a_h[10]), .b_out(b_v[10]), .c_acc(pe_c[7]));
    pe #(.DW(DW), .AW(AW)) u_pe_22 (.clk(clk), .rst_n(rst_n), .clear(pe_clear),
        .a_in(a_h[10]), .b_in(b_v[8]), .a_out(a_h[11]), .b_out(b_v[11]), .c_acc(pe_c[8]));

    assign c_out[0*AW +: AW] = pe_c[0];
    assign c_out[1*AW +: AW] = pe_c[1];
    assign c_out[2*AW +: AW] = pe_c[2];
    assign c_out[3*AW +: AW] = pe_c[3];
    assign c_out[4*AW +: AW] = pe_c[4];
    assign c_out[5*AW +: AW] = pe_c[5];
    assign c_out[6*AW +: AW] = pe_c[6];
    assign c_out[7*AW +: AW] = pe_c[7];
    assign c_out[8*AW +: AW] = pe_c[8];

endmodule
