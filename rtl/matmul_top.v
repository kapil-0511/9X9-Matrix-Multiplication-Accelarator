// Top-level: 9x9 x 9x9 tiled matrix multiplier.
// SRAM arbiter gives tile_controller exclusive access when busy;
// APB accesses SRAM only when idle.

module matmul_top (
    input  wire        pclk,
    input  wire        presetn,
    // APB
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr
);
    wire        apb_we,  tc_we,  sram_we;
    wire [7:0]  apb_addr, tc_addr, sram_addr;
    wire [31:0] apb_wdata, tc_wdata, sram_wdata, sram_rdata;
    wire        ctrl_start, stat_done, stat_busy;
    wire [287:0] a_buf_flat, b_buf_flat;
    wire [575:0] mac_c_flat;
    wire         mac_start, mac_done;


    assign sram_we    = stat_busy ? tc_we    : apb_we;
    assign sram_addr  = stat_busy ? tc_addr  : apb_addr;
    assign sram_wdata = stat_busy ? tc_wdata : apb_wdata;

    apb_slave u_apb (
        .pclk       (pclk),
        .presetn    (presetn),
        .psel       (psel),
        .penable    (penable),
        .pwrite     (pwrite),
        .paddr      (paddr),
        .pwdata     (pwdata),
        .prdata     (prdata),
        .pready     (pready),
        .pslverr    (pslverr),
        .apb_we     (apb_we),
        .apb_addr   (apb_addr),
        .apb_wdata  (apb_wdata),
        .apb_rdata  (sram_rdata),
        .ctrl_start (ctrl_start),
        .stat_done  (stat_done),
        .stat_busy  (stat_busy)
    );

    sram #(
        .DEPTH (256),
        .AW    (8),
        .DW    (32)
    ) u_sram (
        .clk   (pclk),
        .we    (sram_we),
        .addr  (sram_addr),
        .wdata (sram_wdata),
        .rdata (sram_rdata)
    );

    tile_controller #(
        .DW (32),
        .AW (64)
    ) u_tc (
        .clk        (pclk),
        .rst_n      (presetn),
        .start      (ctrl_start),
        .busy       (stat_busy),
        .done       (stat_done),
        .sram_we    (tc_we),
        .sram_addr  (tc_addr),
        .sram_wdata (tc_wdata),
        .sram_rdata (sram_rdata),
        .a_buf_out  (a_buf_flat),
        .b_buf_out  (b_buf_flat),
        .mac_start  (mac_start),
        .mac_c_in   (mac_c_flat),
        .mac_done   (mac_done)
    );

    mac_array_3x3 #(
        .DW (32),
        .AW (64)
    ) u_mac (
        .clk   (pclk),
        .rst_n (presetn),
        .start (mac_start),
        .done  (mac_done),
        .a_buf (a_buf_flat),
        .b_buf (b_buf_flat),
        .c_out (mac_c_flat)
    );

endmodule
