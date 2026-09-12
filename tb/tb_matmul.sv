// Testbench: 9x9 x 9x9 tiled matrix multiplier, 4 test cases.

`timescale 1ns/1ps

module tb_matmul;

    logic pclk = 0;
    always #5 pclk = ~pclk;

    logic presetn;
    initial begin presetn = 0; #27; @(posedge pclk); presetn = 1; end

    logic        psel, penable, pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready, pslverr;

    matmul_top dut (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel),
        .penable (penable),
        .pwrite  (pwrite),
        .paddr   (paddr),
        .pwdata  (pwdata),
        .prdata  (prdata),
        .pready  (pready),
        .pslverr (pslverr)
    );

    // APB tasks hold penable until pready=1 (spec-compliant, works with any slave latency).
    task automatic apb_write(input logic [11:0] addr, input logic [31:0] data);
        @(posedge pclk); #1;
        psel = 1; penable = 0; pwrite = 1; paddr = addr; pwdata = data;
        @(posedge pclk); #1;
        penable = 1;
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        #1;
        psel = 0; penable = 0; pwrite = 0;
    endtask

    task automatic apb_read(input logic [11:0] addr, output logic [31:0] data);
        @(posedge pclk); #1;
        psel = 1; penable = 0; pwrite = 0; paddr = addr;
        @(posedge pclk); #1;
        penable = 1;
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        #1;          // combinational prdata settles after posedge
        data = prdata;
        psel = 0; penable = 0;
    endtask

    logic signed [31:0] A_in [0:8][0:8];
    logic signed [31:0] B_in [0:8][0:8];
    int total_pass, total_fail;
    task automatic run_test(input string test_name);
        logic signed [63:0] C_ref [0:8][0:8];
        logic        [31:0] C_dut [0:8][0:8];
        logic        [31:0] status;
        int                 pass_cnt, fail_cnt;

        $display("\n------------------------------------------------------------");
        $display("  TEST: %s", test_name);
        $display("------------------------------------------------------------");

        for (int i = 0; i < 9; i++)
            for (int j = 0; j < 9; j++) begin
                C_ref[i][j] = 0;
                for (int k = 0; k < 9; k++)
                    C_ref[i][j] += A_in[i][k] * B_in[k][j];
            end


        $display("\n  Input matrix A (9x9):");
        $display("         c0     c1     c2     c3     c4     c5     c6     c7     c8");
        for (int i = 0; i < 9; i++) begin
            $write("    r%0d:", i);
            for (int j = 0; j < 9; j++)
                $write(" %6d", A_in[i][j]);
            $write("\n");
        end

        $display("\n  Input matrix B (9x9):");
        $display("         c0     c1     c2     c3     c4     c5     c6     c7     c8");
        for (int i = 0; i < 9; i++) begin
            $write("    r%0d:", i);
            for (int j = 0; j < 9; j++)
                $write(" %6d", B_in[i][j]);
            $write("\n");
        end

        $display("\n  t=%0t  Loading A...", $time);
        for (int i = 0; i < 9; i++)
            for (int j = 0; j < 9; j++)
                apb_write(12'h000 + 12'((i*9+j) << 2), A_in[i][j]);

        $display("  t=%0t  Loading B...", $time);
        for (int i = 0; i < 9; i++)
            for (int j = 0; j < 9; j++)
                apb_write(12'h200 + 12'((i*9+j) << 2), B_in[i][j]);

        $display("  t=%0t  Start!", $time);
        apb_write(12'h600, 32'h1);

        status = 0;
        while (!status[0]) begin
            repeat(10) @(posedge pclk);
            apb_read(12'h604, status);
        end
        $display("  t=%0t  Done!", $time);

        for (int i = 0; i < 9; i++)
            for (int j = 0; j < 9; j++)
                apb_read(12'h400 + 12'((i*9+j) << 2), C_dut[i][j]);

        pass_cnt = 0; fail_cnt = 0;
        for (int i = 0; i < 9; i++)
            for (int j = 0; j < 9; j++) begin
                if (C_dut[i][j] === C_ref[i][j][31:0])
                    pass_cnt++;
                else begin
                    $display("  FAIL C[%0d][%0d]  got=%-8d  exp=%-8d",
                             i, j, $signed(C_dut[i][j]), C_ref[i][j][31:0]);
                    fail_cnt++;
                end
            end

        $display("\n  Output matrix C = A x B:");
        $display("         c0     c1     c2     c3     c4     c5     c6     c7     c8");
        for (int i = 0; i < 9; i++) begin
            $write("    r%0d:", i);
            for (int j = 0; j < 9; j++)
                $write(" %6d", $signed(C_dut[i][j]));
            $write("\n");
        end

        $display("\n  Golden reference C_ref = A x B (software):");
        $display("         c0     c1     c2     c3     c4     c5     c6     c7     c8");
        for (int i = 0; i < 9; i++) begin
            $write("    r%0d:", i);
            for (int j = 0; j < 9; j++)
                $write(" %6d", $signed(C_ref[i][j][31:0]));
            $write("\n");
        end

        $display("\n  %s  ->  %0d PASS  |  %0d FAIL",
                 test_name, pass_cnt, fail_cnt);

        total_pass += pass_cnt;
        total_fail += fail_cnt;
    endtask

    initial begin
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        total_pass = 0; total_fail = 0;

        @(posedge presetn);
        repeat(5) @(posedge pclk);

        // 10 tests with escalating ranges; max result = 9*N*N, all < 2^31
        begin
            automatic int    ranges[10] = '{10, 20, 50, 100, 150, 200, 300, 500, 750, 1000};
            automatic string names[10]  = '{
                "T01: random [-10..10]",
                "T02: random [-20..20]",
                "T03: random [-50..50]",
                "T04: random [-100..100]",
                "T05: random [-150..150]",
                "T06: random [-200..200]",
                "T07: random [-300..300]",
                "T08: random [-500..500]",
                "T09: random [-750..750]",
                "T10: random [-1000..1000]"
            };

            for (int t = 0; t < 10; t++) begin
                for (int i = 0; i < 9; i++)
                    for (int j = 0; j < 9; j++) begin
                        A_in[i][j] = $signed(32'($urandom_range(0, 2*ranges[t]))) - ranges[t];
                        B_in[i][j] = $signed(32'($urandom_range(0, 2*ranges[t]))) - ranges[t];
                    end
                run_test(names[t]);
            end
        end

        $display("\n============================================================");
        $display("  GRAND TOTAL:  %0d PASS  |  %0d FAIL  (10 tests x 81 elements)",
                 total_pass, total_fail);
        $display("============================================================\n");
        $finish;
    end

    initial begin
        #250_000_000;
        $display("TIMEOUT at %0t ns", $time);
        $finish;
    end

    initial begin
        $dumpfile("tb_matmul.vcd");
        $dumpvars(0, tb_matmul);
    end

endmodule
