// Tiling FSM for 9x9 x 9x9 matrix multiply with 3x3 tiles.
//
// Loop order (A-stationary): br → bc → bk
//   For each (br,bc): clear C_acc, iterate bk, accumulate mac_out, write C.
//
// sram_addr is combinational so SRAM sees the address at posedge N
// and rdata is valid at posedge N+1 (synchronous SRAM read latency).
//
// SRAM layout:  A[r][c] = addr r*9+c (0..80)
//               B[r][c] = addr 81+r*9+c (81..161)
//               C[r][c] = addr 162+r*9+c (162..242)

module tile_controller #(
    parameter DW = 32,
    parameter AW = 64
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,
    output reg             busy,
    output reg             done,
    // SRAM port — combinational outputs for correct read timing
    output reg             sram_we,
    output reg  [7:0]      sram_addr,
    output reg  [31:0]     sram_wdata,
    input  wire [31:0]     sram_rdata,
    // MAC array ports (flat vectors, row-major)
    output wire [9*DW-1:0] a_buf_out,
    output wire [9*DW-1:0] b_buf_out,
    output reg             mac_start,
    input  wire [9*AW-1:0] mac_c_in,
    input  wire            mac_done
);

    // State encoding
    localparam ST_IDLE         = 4'd0;
    localparam ST_CLEAR_ACC    = 4'd1;
    localparam ST_LOAD_A       = 4'd2;
    localparam ST_LOAD_A_LATCH = 4'd3;
    localparam ST_LOAD_B       = 4'd4;
    localparam ST_LOAD_B_LATCH = 4'd5;
    localparam ST_COMPUTE      = 4'd6;
    localparam ST_ADD_PARTIAL  = 4'd7;
    localparam ST_BK_INC       = 4'd8;
    localparam ST_WRITE_C      = 4'd9;
    localparam ST_BC_INC       = 4'd10;
    localparam ST_BR_INC       = 4'd11;
    localparam ST_DONE         = 4'd12;

    reg [3:0] state;

    reg [1:0] br, bc, bk;
    reg [3:0] elem_cnt;

    reg [DW-1:0] a_buf_r [0:8];
    reg [DW-1:0] b_buf_r [0:8];
    reg [AW-1:0] c_acc   [0:8];

    assign a_buf_out[0*DW +: DW] = a_buf_r[0];
    assign a_buf_out[1*DW +: DW] = a_buf_r[1];
    assign a_buf_out[2*DW +: DW] = a_buf_r[2];
    assign a_buf_out[3*DW +: DW] = a_buf_r[3];
    assign a_buf_out[4*DW +: DW] = a_buf_r[4];
    assign a_buf_out[5*DW +: DW] = a_buf_r[5];
    assign a_buf_out[6*DW +: DW] = a_buf_r[6];
    assign a_buf_out[7*DW +: DW] = a_buf_r[7];
    assign a_buf_out[8*DW +: DW] = a_buf_r[8];

    assign b_buf_out[0*DW +: DW] = b_buf_r[0];
    assign b_buf_out[1*DW +: DW] = b_buf_r[1];
    assign b_buf_out[2*DW +: DW] = b_buf_r[2];
    assign b_buf_out[3*DW +: DW] = b_buf_r[3];
    assign b_buf_out[4*DW +: DW] = b_buf_r[4];
    assign b_buf_out[5*DW +: DW] = b_buf_r[5];
    assign b_buf_out[6*DW +: DW] = b_buf_r[6];
    assign b_buf_out[7*DW +: DW] = b_buf_r[7];
    assign b_buf_out[8*DW +: DW] = b_buf_r[8];

    reg [1:0] elem_i, elem_j;
    always @(*) begin
        case (elem_cnt)
            4'd0: begin elem_i = 2'd0; elem_j = 2'd0; end
            4'd1: begin elem_i = 2'd0; elem_j = 2'd1; end
            4'd2: begin elem_i = 2'd0; elem_j = 2'd2; end
            4'd3: begin elem_i = 2'd1; elem_j = 2'd0; end
            4'd4: begin elem_i = 2'd1; elem_j = 2'd1; end
            4'd5: begin elem_i = 2'd1; elem_j = 2'd2; end
            4'd6: begin elem_i = 2'd2; elem_j = 2'd0; end
            4'd7: begin elem_i = 2'd2; elem_j = 2'd1; end
            4'd8: begin elem_i = 2'd2; elem_j = 2'd2; end
            default: begin elem_i = 2'd0; elem_j = 2'd0; end
        endcase
    end

    wire [3:0] row_a = br * 4'd3 + {2'b0, elem_i};
    wire [3:0] col_a = bk * 4'd3 + {2'b0, elem_j};
    wire [3:0] row_b = bk * 4'd3 + {2'b0, elem_i};
    wire [3:0] col_b = bc * 4'd3 + {2'b0, elem_j};
    wire [3:0] row_c = br * 4'd3 + {2'b0, elem_i};
    wire [3:0] col_c = bc * 4'd3 + {2'b0, elem_j};

    // addr = row*9 + col, implemented as (row<<3) + row + col
    wire [6:0] a_addr7 = ({row_a, 3'b000} + {3'b000, row_a}) + {3'b000, col_a};
    wire [6:0] b_addr7 = ({row_b, 3'b000} + {3'b000, row_b}) + {3'b000, col_b};
    wire [6:0] c_addr7 = ({row_c, 3'b000} + {3'b000, row_c}) + {3'b000, col_c};

    wire [7:0] a_elem_addr = {1'b0, a_addr7};
    wire [7:0] b_elem_addr = 8'd81  + {1'b0, b_addr7};
    wire [7:0] c_elem_addr = 8'd162 + {1'b0, c_addr7};

    always @(*) begin
        sram_we    = 1'b0;
        sram_addr  = 8'd0;
        sram_wdata = 32'd0;
        case (state)
            ST_LOAD_A, ST_LOAD_A_LATCH: begin
                sram_we   = 1'b0;
                sram_addr = a_elem_addr;
            end
            ST_LOAD_B, ST_LOAD_B_LATCH: begin
                sram_we   = 1'b0;
                sram_addr = b_elem_addr;
            end
            ST_WRITE_C: begin
                sram_we    = 1'b1;
                sram_addr  = c_elem_addr;
                sram_wdata = c_acc[elem_cnt][31:0];
            end
            default: begin
                sram_we    = 1'b0;
                sram_addr  = 8'd0;
                sram_wdata = 32'd0;
            end
        endcase
    end

    integer n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            br        <= 2'd0; bc <= 2'd0; bk <= 2'd0;
            elem_cnt  <= 4'd0;
            mac_start <= 1'b0;
            for (n = 0; n < 9; n = n + 1) begin
                a_buf_r[n] <= {DW{1'b0}};
                b_buf_r[n] <= {DW{1'b0}};
                c_acc[n]   <= {AW{1'b0}};
            end
        end else begin
            mac_start <= 1'b0;
            // done is sticky — cleared only when next start fires (ST_IDLE)

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        done  <= 1'b0;
                        busy  <= 1'b1;
                        br    <= 2'd0; bc <= 2'd0; bk <= 2'd0;
                        state <= ST_CLEAR_ACC;
                    end
                end

                ST_CLEAR_ACC: begin
                    for (n = 0; n < 9; n = n + 1)
                        c_acc[n] <= {AW{1'b0}};
                    elem_cnt <= 4'd0;
                    state    <= ST_LOAD_A;
                end

                ST_LOAD_A: begin
                    state <= ST_LOAD_A_LATCH;
                end

                ST_LOAD_A_LATCH: begin
                    a_buf_r[elem_cnt] <= sram_rdata;
                    if (elem_cnt == 4'd8) begin
                        elem_cnt <= 4'd0;
                        state    <= ST_LOAD_B;
                    end else begin
                        elem_cnt <= elem_cnt + 4'd1;
                        state    <= ST_LOAD_A;
                    end
                end

                ST_LOAD_B: begin
                    state <= ST_LOAD_B_LATCH;
                end

                ST_LOAD_B_LATCH: begin
                    b_buf_r[elem_cnt] <= sram_rdata;
                    if (elem_cnt == 4'd8) begin
                        elem_cnt  <= 4'd0;
                        mac_start <= 1'b1;
                        state     <= ST_COMPUTE;
                    end else begin
                        elem_cnt <= elem_cnt + 4'd1;
                        state    <= ST_LOAD_B;
                    end
                end

                ST_COMPUTE: begin
                    if (mac_done)
                        state <= ST_ADD_PARTIAL;
                end

                ST_ADD_PARTIAL: begin
                    for (n = 0; n < 9; n = n + 1)
                        c_acc[n] <= $signed(c_acc[n]) +
                                    $signed(mac_c_in[n*AW +: AW]);
                    state <= ST_BK_INC;
                end

                ST_BK_INC: begin
                    if (bk == 2'd2) begin
                        bk       <= 2'd0;
                        elem_cnt <= 4'd0;
                        state    <= ST_WRITE_C;
                    end else begin
                        bk    <= bk + 2'd1;
                        state <= ST_LOAD_A;
                    end
                end

                ST_WRITE_C: begin
                    if (elem_cnt == 4'd8) begin
                        elem_cnt <= 4'd0;
                        state    <= ST_BC_INC;
                    end else begin
                        elem_cnt <= elem_cnt + 4'd1;
                    end
                end

                ST_BC_INC: begin
                    if (bc == 2'd2) begin
                        bc    <= 2'd0;
                        state <= ST_BR_INC;
                    end else begin
                        bc    <= bc + 2'd1;
                        state <= ST_CLEAR_ACC;
                    end
                end

                ST_BR_INC: begin
                    if (br == 2'd2) begin
                        state <= ST_DONE;
                    end else begin
                        br    <= br + 2'd1;
                        state <= ST_CLEAR_ACC;
                    end
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
