
`timescale 1ns/1ps

module tb_voxel_scatter_addr_gen;

    // =========================================================
    // 参数
    // =========================================================
    localparam integer GRID_WIDTH    = 720;
    localparam integer BYTES_PER_VOX = 128;
    localparam integer DATA_BYTES    = 96;
    localparam integer COORD_WIDTH   = 11;

    // =========================================================
    // DUT 端口信号
    // =========================================================
    reg                      aclk;
    reg                      aresetn;
    reg      [31:0]          base_addr_in;
    reg                      s_voxel_valid;
    reg      [COORD_WIDTH-1:0] s_voxel_x;
    reg      [COORD_WIDTH-1:0] s_voxel_y;

    wire                     m_axis_cmd_tvalid;
    reg                      m_axis_cmd_tready;
    wire     [71:0]          m_axis_cmd_tdata;

    // =========================================================
    // DUT 实例化
    // =========================================================
    voxel_scatter_addr_gen #(
        .GRID_WIDTH   (GRID_WIDTH),
        .BYTES_PER_VOX(BYTES_PER_VOX),
        .DATA_BYTES   (DATA_BYTES),
        .COORD_WIDTH  (COORD_WIDTH)
    ) dut (
        .aclk              (aclk),
        .aresetn           (aresetn),
        .base_addr_in      (base_addr_in),
        .s_voxel_valid     (s_voxel_valid),
        .s_voxel_x         (s_voxel_x),
        .s_voxel_y         (s_voxel_y),
        .m_axis_cmd_tvalid (m_axis_cmd_tvalid),
        .m_axis_cmd_tready (m_axis_cmd_tready),
        .m_axis_cmd_tdata  (m_axis_cmd_tdata)
    );

    // =========================================================
    // 时钟
    // =========================================================
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;   // 100MHz
    end

    // =========================================================
    // 参考模型 / 检查函数
    // =========================================================
    function [31:0] calc_addr;
        input [31:0] base;
        input [COORD_WIDTH-1:0] x;
        input [COORD_WIDTH-1:0] y;
        reg   [31:0] ux, uy;
        begin
            ux = x;
            uy = y;
            calc_addr = base + (ux << 7) + (uy * GRID_WIDTH * BYTES_PER_VOX);
            // 等价于: base + x*128 + y*92160
        end
    endfunction

    function [71:0] build_cmd;
        input [31:0] addr;
        begin
            build_cmd = {
                4'b0000,   // [71:68]
                4'b0000,   // [67:64]
                addr,      // [63:32]
                1'b0,      // [31] DRR
                1'b1,      // [30] EOF
                6'b000000, // [29:24] DSA
                1'b1,      // [23] Type=INCR
                23'd96     // [22:0] BTT
            };
        end
    endfunction

    task expect_cmd;
        input [31:0] exp_addr;
        input        exp_valid;
        reg   [71:0] exp_data;
        begin
            exp_data = build_cmd(exp_addr);

            if (m_axis_cmd_tvalid !== exp_valid) begin
                $display("[%0t] ERROR: tvalid mismatch. exp=%0d, got=%0d",
                         $time, exp_valid, m_axis_cmd_tvalid);
                $fatal;
            end

            if (exp_valid) begin
                if (m_axis_cmd_tdata !== exp_data) begin
                    $display("[%0t] ERROR: tdata mismatch.", $time);
                    $display("        exp = 0x%018h", exp_data);
                    $display("        got = 0x%018h", m_axis_cmd_tdata);
                    $fatal;
                end
            end
        end
    endtask

    // =========================================================
    // 激励
    // =========================================================
    reg [31:0] exp_addr_hold;
    reg [71:0] exp_cmd_hold;

    initial begin
        // 初始化
        aresetn           = 1'b0;
        base_addr_in      = 32'h1000_0000;
        s_voxel_valid     = 1'b0;
        s_voxel_x         = {COORD_WIDTH{1'b0}};
        s_voxel_y         = {COORD_WIDTH{1'b0}};
        m_axis_cmd_tready = 1'b0;

        // 复位阶段
        repeat (3) @(posedge aclk);
        #1;
        expect_cmd(32'd0, 1'b0);

        // 释放复位
        aresetn = 1'b1;
        @(posedge aclk);
        #1;
        expect_cmd(32'd0, 1'b0);

        // =====================================================
        // CASE 1:
        // ready=1, valid=1，装载第一个命令
        // 坐标 (x=3, y=2)
        // addr = base + 3*128 + 2*92160
        // =====================================================
        m_axis_cmd_tready = 1'b1;
        s_voxel_valid     = 1'b1;
        s_voxel_x         = 11'd3;
        s_voxel_y         = 11'd2;
        base_addr_in      = 32'h1000_0000;

        @(posedge aclk);
        #1;
        exp_addr_hold = calc_addr(32'h1000_0000, 11'd3, 11'd2);
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE1 PASS: addr = 0x%08h", $time, exp_addr_hold);

        // 输入撤销
        s_voxel_valid = 1'b0;

        // 因为 ready=1，下一个周期 cmd_valid 会被更新为 0
        @(posedge aclk);
        #1;
        expect_cmd(exp_addr_hold, 1'b0);
        $display("[%0t] CASE2 PASS: valid deasserted correctly", $time);

        // =====================================================
        // CASE 2:
        // 再发一个新点 (x=10, y=5)
        // =====================================================
        s_voxel_valid = 1'b1;
        s_voxel_x     = 11'd10;
        s_voxel_y     = 11'd5;
        base_addr_in  = 32'h2000_0000;
        m_axis_cmd_tready = 1'b1;

        @(posedge aclk);
        #1;
        exp_addr_hold = calc_addr(32'h2000_0000, 11'd10, 11'd5);
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE3 PASS: addr = 0x%08h", $time, exp_addr_hold);

        // =====================================================
        // CASE 3:
        // 下游不 ready，命令应保持
        // =====================================================
        m_axis_cmd_tready = 1'b0;

        // 即使输入换成别的，也不应装载新命令
        s_voxel_valid = 1'b1;
        s_voxel_x     = 11'd100;
        s_voxel_y     = 11'd200;
        base_addr_in  = 32'h3000_0000;

        @(posedge aclk);
        #1;
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE4 PASS: hold command while not ready", $time);

        @(posedge aclk);
        #1;
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE5 PASS: command still stable while stalled", $time);

        // =====================================================
        // CASE 4:
        // 恢复 ready 后，应该装载当前输入对应的新命令
        // =====================================================
        m_axis_cmd_tready = 1'b1;

        @(posedge aclk);
        #1;
        exp_addr_hold = calc_addr(32'h3000_0000, 11'd100, 11'd200);
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE6 PASS: load new command after ready returns, addr=0x%08h",
                 $time, exp_addr_hold);

        // =====================================================
        // CASE 5:
        // 检查命令字段固定值
        // =====================================================
        if (m_axis_cmd_tdata[71:68] !== 4'b0000) begin
            $display("[%0t] ERROR: RSVD field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[67:64] !== 4'b0000) begin
            $display("[%0t] ERROR: TAG field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[31] !== 1'b0) begin
            $display("[%0t] ERROR: DRR field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[30] !== 1'b1) begin
            $display("[%0t] ERROR: EOF field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[29:24] !== 6'b000000) begin
            $display("[%0t] ERROR: DSA field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[23] !== 1'b1) begin
            $display("[%0t] ERROR: Type field mismatch", $time);
            $fatal;
        end
        if (m_axis_cmd_tdata[22:0] !== 23'd96) begin
            $display("[%0t] ERROR: BTT field mismatch", $time);
            $fatal;
        end
        $display("[%0t] CASE7 PASS: command field constants are correct", $time);

        // =====================================================
        // CASE 6:
        // 边界值简单检查
        // =====================================================
        s_voxel_valid = 1'b1;
        s_voxel_x     = {COORD_WIDTH{1'b1}}; // 2047
        s_voxel_y     = {COORD_WIDTH{1'b1}}; // 2047
        base_addr_in  = 32'h0000_1000;
        m_axis_cmd_tready = 1'b1;

        @(posedge aclk);
        #1;
        exp_addr_hold = calc_addr(32'h0000_1000, {COORD_WIDTH{1'b1}}, {COORD_WIDTH{1'b1}});
        expect_cmd(exp_addr_hold, 1'b1);
        $display("[%0t] CASE8 PASS: boundary input addr=0x%08h", $time, exp_addr_hold);

        $display("==================================================");
        $display(" All test cases PASSED.");
        $display("==================================================");
        $finish;
    end

endmodule