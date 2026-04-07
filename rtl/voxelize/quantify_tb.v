`timescale 1ns/1ps

// ============================================================
// DUT: 仅保留待测函数（与 pfe.v 中一致）
// ============================================================
module quant_func_dut;

    function automatic signed [7:0] sat_int8;
        input signed [31:0] din;
        begin
            if (din > 32'sd127) sat_int8 = 8'sd127;
            else if (din < -32'sd127) sat_int8 = -8'sd127;
            else sat_int8 = din[7:0];
        end
    endfunction

    function automatic signed [7:0] quant_xy_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult;
        reg signed [31:0] roundv;
        reg signed [31:0] shifted;
        begin
            mult = din_q9 * 32'sd151;
            if (mult >= 0) roundv = mult + 32'sd16384;
            else roundv = mult - 32'sd16384;
            shifted = roundv >>> 15;
            quant_xy_q9 = sat_int8(shifted);
        end
    endfunction

    function automatic signed [7:0] quant_z_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult;
        reg signed [31:0] roundv;
        reg signed [31:0] shifted;
        begin
            mult = din_q9 * 32'sd1626;
            if (mult >= 0) roundv = mult + 32'sd16384;
            else roundv = mult - 32'sd16384;
            shifted = roundv >>> 15;
            quant_z_q9 = sat_int8(shifted);
        end
    endfunction

    function automatic signed [7:0] quant_int_u16;
        input [15:0] din_u16;
        reg [31:0] mult;
        reg [31:0] shifted;
        begin
            mult = din_u16 * 32'd16320;
            shifted = (mult + 32'd16384) >> 15;
            if (shifted > 32'd127) quant_int_u16 = 8'sd127;
            else quant_int_u16 = $signed(shifted[7:0]);
        end
    endfunction

    function automatic signed [7:0] quant_dxy_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult;
        reg signed [31:0] roundv;
        reg signed [31:0] shifted;
        begin
            mult = din_q9 * 32'sd6773;
            if (mult >= 0) roundv = mult + 32'sd2048;
            else roundv = mult - 32'sd2048;
            shifted = roundv >>> 12;
            quant_dxy_q9 = sat_int8(shifted);
        end
    endfunction

endmodule


// ============================================================
// TB
// ============================================================
module tb_quant_func;

    quant_func_dut dut();

    integer err_cnt;
    integer i;
    integer random_print_limit;

    // -------------------------
    // 参考模型（与 DUT 同公式）
    // -------------------------
    function automatic signed [7:0] ref_sat_int8;
        input signed [31:0] din;
        begin
            if (din > 32'sd127) ref_sat_int8 = 8'sd127;
            else if (din < -32'sd127) ref_sat_int8 = -8'sd127;
            else ref_sat_int8 = din[7:0];
        end
    endfunction

    function automatic signed [7:0] ref_quant_xy_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult, roundv, shifted;
        begin
            mult = din_q9 * 32'sd151;
            if (mult >= 0) roundv = mult + 32'sd16384;
            else roundv = mult - 32'sd16384;
            shifted = roundv >>> 15;
            ref_quant_xy_q9 = ref_sat_int8(shifted);
        end
    endfunction

    function automatic signed [7:0] ref_quant_z_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult, roundv, shifted;
        begin
            mult = din_q9 * 32'sd1626;
            if (mult >= 0) roundv = mult + 32'sd16384;
            else roundv = mult - 32'sd16384;
            shifted = roundv >>> 15;
            ref_quant_z_q9 = ref_sat_int8(shifted);
        end
    endfunction

    function automatic signed [7:0] ref_quant_int_u16;
        input [15:0] din_u16;
        reg [31:0] mult, shifted;
        begin
            mult = din_u16 * 32'd16320;
            shifted = (mult + 32'd16384) >> 15;
            if (shifted > 32'd127) ref_quant_int_u16 = 8'sd127;
            else ref_quant_int_u16 = $signed(shifted[7:0]);
        end
    endfunction

    function automatic signed [7:0] ref_quant_dxy_q9;
        input signed [15:0] din_q9;
        reg signed [31:0] mult, roundv, shifted;
        begin
            mult = din_q9 * 32'sd6773;
            if (mult >= 0) roundv = mult + 32'sd2048;
            else roundv = mult - 32'sd2048;
            shifted = roundv >>> 12;
            ref_quant_dxy_q9 = ref_sat_int8(shifted);
        end
    endfunction

    // -------------------------
    // 检查任务
    // -------------------------
    task automatic check_xy(input signed [15:0] din, input show_log);
        reg signed [7:0] got, exp;
        begin
            got = dut.quant_xy_q9(din);
            exp = ref_quant_xy_q9(din);
            if (show_log) begin
                $display("[XY ] in_q9=%0d -> out_q8=%0d (ref=%0d)", din, got, exp);
            end
            if (got !== exp) begin
                err_cnt = err_cnt + 1;
                $display("[XY][ERR] din=%0d got=%0d exp=%0d", din, got, exp);
            end
        end
    endtask

    task automatic check_z(input signed [15:0] din, input show_log);
        reg signed [7:0] got, exp;
        begin
            got = dut.quant_z_q9(din);
            exp = ref_quant_z_q9(din);
            if (show_log) begin
                $display("[Z  ] in_q9=%0d -> out_q8=%0d (ref=%0d)", din, got, exp);
            end
            if (got !== exp) begin
                err_cnt = err_cnt + 1;
                $display("[Z ][ERR] din=%0d got=%0d exp=%0d", din, got, exp);
            end
        end
    endtask

    task automatic check_dxy(input signed [15:0] din, input show_log);
        reg signed [7:0] got, exp;
        begin
            got = dut.quant_dxy_q9(din);
            exp = ref_quant_dxy_q9(din);
            if (show_log) begin
                $display("[DXY] in_q9=%0d -> out_q8=%0d (ref=%0d)", din, got, exp);
            end
            if (got !== exp) begin
                err_cnt = err_cnt + 1;
                $display("[DXY][ERR] din=%0d got=%0d exp=%0d", din, got, exp);
            end
        end
    endtask

    task automatic check_int(input [15:0] din, input show_log);
        reg signed [7:0] got, exp;
        begin
            got = dut.quant_int_u16(din);
            exp = ref_quant_int_u16(din);
            if (show_log) begin
                $display("[INT] in_u16=%0d -> out_q8=%0d (ref=%0d)", din, got, exp);
            end
            if (got !== exp) begin
                err_cnt = err_cnt + 1;
                $display("[INT][ERR] din=%0d got=%0d exp=%0d", din, got, exp);
            end
        end
    endtask

    // -------------------------
    // 主测试流程
    // -------------------------
    initial begin
        err_cnt = 0;
        random_print_limit = 20;

        $display("======================================");
        $display("Quantization check log (before -> after)");
        $display("======================================");

        // Directed cases
        // Q9: 54.0 = 27648, -54.0 = -27648
        check_xy(16'sd0, 1'b1);
        check_xy(16'sd27648, 1'b1);
        check_xy(-16'sd27648, 1'b1);
        check_xy(16'sd32767, 1'b1);
        check_xy(-16'sd32768, 1'b1);

        // Q9: z range around [-5, 3] => [-2560, 1536]
        check_z(16'sd0, 1'b1);
        check_z(16'sd1536, 1'b1);
        check_z(-16'sd2560, 1'b1);
        check_z(16'sd32767, 1'b1);
        check_z(-16'sd32768, 1'b1);

        // Q9: dxy around [-0.15,0.15], 0.15*512 ~= 77
        check_dxy(16'sd0, 1'b1);
        check_dxy(16'sd77, 1'b1);
        check_dxy(-16'sd77, 1'b1);
        check_dxy(16'sd1024, 1'b1);
        check_dxy(-16'sd1024, 1'b1);

        // intensity
        check_int(16'd0, 1'b1);
        check_int(16'd1, 1'b1);
        check_int(16'd64, 1'b1);
        check_int(16'd128, 1'b1);
        check_int(16'd255, 1'b1);
        check_int(16'd1023, 1'b1);
        check_int(16'd65535, 1'b1);

        // Random sweep
        $display("---- Random sweep (print first %0d rounds) ----", random_print_limit);
        for (i = 0; i < 1000; i = i + 1) begin
            check_xy($random, (i < random_print_limit));
            check_z($random, (i < random_print_limit));
            check_dxy($random, (i < random_print_limit));
            check_int($random, (i < random_print_limit));
        end

        if (err_cnt == 0) begin
            $display("======================================");
            $display("PASS: all quantization function tests.");
            $display("======================================");
        end else begin
            $display("======================================");
            $display("FAIL: total errors = %0d", err_cnt);
            $display("======================================");
        end

        // $finish;
    end

endmodule