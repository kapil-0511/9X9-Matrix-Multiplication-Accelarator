// APB slave — bridges APB to SRAM and control/status registers.
//
// Address map (byte addresses):
//   0x000–0x143  Matrix A  (81 x 32-bit words)
//   0x200–0x343  Matrix B  (81 x 32-bit words)
//   0x400–0x543  Matrix C  (81 x 32-bit words, read-only)
//   0x600        Control   [0]=start
//   0x604        Status    [0]=done  [1]=busy
//
// Read timing: SETUP phase drives sram_addr combinationally so SRAM latches
// it at that posedge; rdata is valid one cycle later in ACCESS phase.

module apb_slave (
    input  wire        pclk,
    input  wire        presetn,
    // APB
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    // SRAM port (to arbiter in top)
    output reg         apb_we,
    output reg  [7:0]  apb_addr,
    output reg  [31:0] apb_wdata,
    input  wire [31:0] apb_rdata,
    // Control / Status
    output reg         ctrl_start,
    input  wire        stat_done,
    input  wire        stat_busy
);
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // B region has paddr[9]=1 for all addresses, so word offset uses paddr[8:2]
    wire sel_a    = (paddr[11:9] == 3'b000) && (paddr[9:2]        <= 8'd80);
    wire sel_b    = (paddr[11:9] == 3'b001) && ({1'b0, paddr[8:2]} <= 8'd80);
    wire sel_c    = (paddr[11:10] == 2'b01) && (paddr[9:2]        <= 8'd80);
    wire sel_ctrl = (paddr == 12'h600);
    wire sel_stat = (paddr == 12'h604);

    // Combinational SRAM drive: reads in SETUP+ACCESS, writes only in ACCESS
    always @(*) begin
        apb_we     = 1'b0;
        apb_addr   = 8'd0;
        apb_wdata  = 32'd0;
        ctrl_start = 1'b0;

        if (psel) begin
            if (pwrite && penable) begin
                if (sel_a) begin
                    apb_we    = 1'b1;
                    apb_addr  = paddr[9:2];
                    apb_wdata = pwdata;
                end else if (sel_b) begin
                    apb_we    = 1'b1;
                    apb_addr  = 8'd81 + {1'b0, paddr[8:2]};
                    apb_wdata = pwdata;
                end else if (sel_ctrl) begin
                    ctrl_start = pwdata[0];
                end
            end else if (!pwrite) begin
                if (sel_a)
                    apb_addr = paddr[9:2];
                else if (sel_b)
                    apb_addr = 8'd81 + paddr[9:2];
                else if (sel_c)
                    apb_addr = 8'd162 + paddr[9:2];
            end
        end
    end

    always @(*) begin
        prdata = 32'd0;
        if (psel && penable && !pwrite) begin
            if (sel_a || sel_b || sel_c)
                prdata = apb_rdata;
            else if (sel_stat)
                prdata = {30'd0, stat_busy, stat_done};
        end
    end
endmodule
