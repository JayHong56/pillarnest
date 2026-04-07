module pfn_layer #(
    parameter EXPAND_PT_DIM   = 11,
    parameter COORD_WIDTH     = 11,
    parameter OUT_PT_DIM      = 48,
    parameter PT_WIDTH        = 16,
    parameter MEM_WEIGHT_FILE = "NOTHING",
    parameter MEM_BIAS_FILE   = "NOTHING",
    parameter WEIGHT_WIDTH    = 16,
    parameter ACC_WIDTH       = 32
) (
    input wire clk,
    input wire rst_n,

    output wire                                     s_axis_pfe_tready,
    input  wire                                     s_axis_pfe_valid,
    input  wire        [EXPAND_PT_DIM*PT_WIDTH-1:0] s_axis_pfe_data,
    input  wire                                     s_axis_pfe_last,
    input  wire                                     s_axis_pfe_voxel_valid,
    input  wire signed [           COORD_WIDTH-1:0] s_axis_pfe_voxel_x,
    input  wire signed [           COORD_WIDTH-1:0] s_axis_pfe_voxel_y,

    output reg                                  m_axis_out_voxel_valid,
    output reg signed [        COORD_WIDTH-1:0] m_axis_out_voxel_x,
    output reg signed [        COORD_WIDTH-1:0] m_axis_out_voxel_y,
    output reg                                  m_axis_out_valid,
    output reg        [OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data,
    output wire                                 m_axis_out_data_bit
);

    assign m_axis_out_data_bit = (m_axis_out_data == {OUT_PT_DIM * PT_WIDTH{1'b1}}) ? 1'b1 : 1'b0;
    localparam HALF_OUT_DIM = OUT_PT_DIM / 2;  // 24

    // 1. 权重与偏置 ROM 
    reg signed [EXPAND_PT_DIM*WEIGHT_WIDTH-1:0] weight_row_rom[0:OUT_PT_DIM-1];
    reg signed [ACC_WIDTH-1:0] bias_rom[0:OUT_PT_DIM-1];

    initial begin
        if (MEM_WEIGHT_FILE != "NOTHING") begin
            $display("Loading weight from %s", MEM_WEIGHT_FILE);
            $readmemh(MEM_WEIGHT_FILE, weight_row_rom);
        end
        if (MEM_BIAS_FILE != "NOTHING") begin
            $display("Loading bias from %s", MEM_BIAS_FILE);
            $readmemh(MEM_BIAS_FILE, bias_rom);
        end
    end

    // =======================================================
    // 级联流水线 Stage 1: 输入锁存与乘法运算 (打一拍)
    // 目标：将长路径在乘法器内部切断，吸收 DSP 的 M 寄存器
    // =======================================================
    reg phase;  // 0: 处理通道 0~23, 1: 处理通道 24~47
    assign s_axis_pfe_tready = (phase == 0);

    // 输入数据的第一级元数据锁存
    reg [EXPAND_PT_DIM*PT_WIDTH-1:0] latched_pfe_data;
    reg latched_last;
    reg latched_voxel_valid;
    reg signed [COORD_WIDTH-1:0] latched_voxel_x;
    reg signed [COORD_WIDTH-1:0] latched_voxel_y;

    // --- 核心流水线寄存器 (Pipeline Registers) ---
    // 这排寄存器就像一堵“挡水大坝”，彻底斩断了原本高达 12ns 的时序爆炸链条
    reg signed [ACC_WIDTH-1:0] st2_mult[0:HALF_OUT_DIM-1][0:EXPAND_PT_DIM-1];
    reg signed [ACC_WIDTH-1:0] st2_bias[0:HALF_OUT_DIM-1];

    // 伴随数据向下游流动的控制信号
    reg st2_valid;
    reg st2_phase;
    reg st2_last;
    reg st2_voxel_valid;
    reg signed [COORD_WIDTH-1:0] st2_voxel_x;
    reg signed [COORD_WIDTH-1:0] st2_voxel_y;

    integer j, k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 1'b0;
            st2_valid <= 1'b0;
            st2_phase <= 1'b0;
            latched_last <= 1'b0;
            latched_voxel_valid <= 1'b0;
        end else begin
            if (phase == 0) begin
                if (s_axis_pfe_valid) begin
                    phase               <= 1'b1;  // 下一拍处理后半区

                    // 锁存供 Phase 1 用的数据
                    latched_pfe_data    <= s_axis_pfe_data;
                    latched_last        <= s_axis_pfe_last;
                    latched_voxel_valid <= s_axis_pfe_voxel_valid;
                    latched_voxel_x     <= s_axis_pfe_voxel_x;
                    latched_voxel_y     <= s_axis_pfe_voxel_y;

                    // --- 第一拍：算出 0~23 通道的乘积，然后【停住】 ---
                    st2_valid           <= 1'b1;
                    st2_phase           <= 1'b0;
                    st2_last            <= s_axis_pfe_last;
                    st2_voxel_valid     <= s_axis_pfe_voxel_valid;
                    st2_voxel_x         <= s_axis_pfe_voxel_x;
                    st2_voxel_y         <= s_axis_pfe_voxel_y;

                    for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                        st2_bias[j] <= ($signed(bias_rom[j]) <<< 8);
                        for (k = 0; k < EXPAND_PT_DIM; k = k + 1) begin
                            // 这里乘完直接存入 st2_mult，必定会被综合为 DSP 内部的 Pipeline 寄存器
                            st2_mult[j][k] <= $signed(
                                s_axis_pfe_data[k*PT_WIDTH+:PT_WIDTH]
                            ) * $signed(
                                weight_row_rom[j][k*WEIGHT_WIDTH+:WEIGHT_WIDTH]
                            );
                        end
                    end
                end else begin
                    st2_valid <= 1'b0;
                end
            end else begin
                // phase == 1 时
                phase <= 1'b0;  // 一点处理完毕，回到接收新点状态

                // --- 第二拍：算出 24~47 通道的乘积，然后【停住】 ---
                st2_valid <= 1'b1;
                st2_phase <= 1'b1;
                st2_last <= latched_last;  // 取出上一拍暂存的控制信号
                st2_voxel_valid <= latched_voxel_valid;
                st2_voxel_x <= latched_voxel_x;
                st2_voxel_y <= latched_voxel_y;

                for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                    st2_bias[j] <= ($signed(bias_rom[j+HALF_OUT_DIM]) <<< 8);
                    for (k = 0; k < EXPAND_PT_DIM; k = k + 1) begin
                        st2_mult[j][k] <= $signed(latched_pfe_data[k*PT_WIDTH+:PT_WIDTH]) *
                            $signed(weight_row_rom[j+HALF_OUT_DIM][k*WEIGHT_WIDTH+:WEIGHT_WIDTH]);
                    end
                end
            end
        end
    end

    // =======================================================
    // 级联流水线 Stage 2: 强制加法树与 ReLU (纯组合逻辑)
    // 此时乘法结果早已准备好，走完加法树只需极短时间 (约 4~5ns)
    // =======================================================
    reg signed [ACC_WIDTH-1:0] mac_tree[0:HALF_OUT_DIM-1];
    reg [PT_WIDTH-1:0] relu_comb[0:HALF_OUT_DIM-1];
    reg signed [63:0] dequant_temp[0:HALF_OUT_DIM-1];  // 改为数组，防止逻辑复用冲突

    always @(*) begin
        for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
            // 【核心修复】：手捏平衡加法树 (Balanced Adder Tree)
            // 通过严格的括号分组，强制 Vivado 综合为深度仅 4 级的加法树，彻底消灭负时序裕量！
            mac_tree[j] = (
            // 左半树
            (
                    (st2_bias[j]      + st2_mult[j][0]) + 
                    (st2_mult[j][1]   + st2_mult[j][2])
                ) + (
                    (st2_mult[j][3]   + st2_mult[j][4]) + 
                     st2_mult[j][5]
                )
            ) + (
            // 右半树
            ((st2_mult[j][6] + st2_mult[j][7]) + (st2_mult[j][8] + st2_mult[j][9])) + (st2_mult[j][10]));

            // 反量化乘法
            dequant_temp[j] = mac_tree[j] * 994;

            // ReLU
            if (mac_tree[j] < 0) relu_comb[j] = 0;
            else relu_comb[j] = dequant_temp[j][PT_WIDTH+20-1 : 20];
        end
    end

    // =======================================================
    // 级联流水线 Stage 3: Max Pool 与 数据输出
    // =======================================================
    reg signed [PT_WIDTH-1:0] max_pool_regs[0:OUT_PT_DIM-1];
    integer oc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_out_valid <= 1'b0;
            m_axis_out_voxel_valid <= 1'b0;
            m_axis_out_voxel_x <= {COORD_WIDTH{1'b0}};
            m_axis_out_voxel_y <= {COORD_WIDTH{1'b0}};
            m_axis_out_data <= 0;
            for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                max_pool_regs[oc] <= 0;
            end
        end else begin
            // 默认拉低单周期脉冲
            m_axis_out_valid <= 1'b0;
            m_axis_out_voxel_valid <= 1'b0;

            if (st2_valid) begin
                if (st2_phase == 0) begin
                    // 【对应前半区计算完毕】：更新前半区 (0~23) 的 Max Pool
                    for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                        if (relu_comb[oc] > max_pool_regs[oc]) begin
                            max_pool_regs[oc] <= relu_comb[oc];
                        end
                    end
                end else begin
                    // 【对应后半区计算完毕】：更新后半区 (24~47) 的 Max Pool
                    for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                        if (relu_comb[oc] > max_pool_regs[oc+HALF_OUT_DIM]) begin
                            max_pool_regs[oc+HALF_OUT_DIM] <= relu_comb[oc];
                        end
                    end

                    // 巧妙对齐：如果这是当前 Voxel 的最后一个点
                    if (st2_last) begin
                        m_axis_out_valid       <= 1'b1;
                        m_axis_out_voxel_valid <= st2_voxel_valid;
                        m_axis_out_voxel_x     <= st2_voxel_x;
                        m_axis_out_voxel_y     <= st2_voxel_y;

                        for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                            // 1. 前半区数据：由于上一拍 (st2_phase==0) 已经更新完了，直接从 max_pool_regs 取出即可
                            m_axis_out_data[oc*PT_WIDTH+:PT_WIDTH] <= max_pool_regs[oc];

                            // 2. 后半区数据：此时本拍正在更新，为了抢时间输出，用三目运算符挑出最大值
                            m_axis_out_data[(oc + HALF_OUT_DIM)*PT_WIDTH +: PT_WIDTH] <= 
                                (relu_comb[oc] > max_pool_regs[oc + HALF_OUT_DIM]) ? relu_comb[oc] : max_pool_regs[oc + HALF_OUT_DIM];

                            // 3. 结算完毕，顺手清空该 Voxel 的所有缓存池，为下一个完美准备
                            max_pool_regs[oc] <= 0;
                            max_pool_regs[oc+HALF_OUT_DIM] <= 0;
                        end
                    end
                end
            end
        end
    end


    // =======================================================
    // 仿真测试探针区 (不可综合)
    // =======================================================
`ifndef SYNTHESIS
    integer csv_fd;
    integer pfe_csv_fd;
    integer pfe_i;
    integer out_i;
    real pfe_q88_val;
    real out_q88_val;

    // 新增：用于输入端累加当前 Voxel 点数的寄存器
    integer pt_cnt;
    // 新增：用于在输出端打印的总点数寄存器
    integer out_pt_cnt;

    initial begin
        pt_cnt = 0;
        out_pt_cnt = 0;

        csv_fd = $fopen("pfn_layer_out.csv", "w");
        if (csv_fd != 0) begin
            // 在第三列 (voxel_y 之后) 增加 pt_cnt 列作为第四列
            $fwrite(csv_fd, "time,voxel_x,voxel_y,pt_cnt");
            for (out_i = 0; out_i < OUT_PT_DIM; out_i = out_i + 1) begin
                $fwrite(csv_fd, ",dim%0d", out_i);
            end
            $fwrite(csv_fd, "\n");
        end

        pfe_csv_fd = $fopen("pfn_layer_pfe_input_dec.csv", "w");
        if (pfe_csv_fd != 0) begin
            // 恢复 PFE 输入的表头原样
            $fwrite(pfe_csv_fd, "time,voxel_x,voxel_y");
            for (pfe_i = EXPAND_PT_DIM - 1; pfe_i >= 0; pfe_i = pfe_i - 1) begin
                $fwrite(pfe_csv_fd, ",dim%0d", pfe_i);
            end
            $fwrite(pfe_csv_fd, "\n");
        end
    end





    // Simulation log: input
    always @(posedge clk) begin
        if (rst_n && s_axis_pfe_valid && s_axis_pfe_tready) begin
            if ((s_axis_pfe_voxel_x == 11'sd287) && (s_axis_pfe_voxel_y == 11'sd368)) begin
                $display("[%0t] DBG voxel(287,368) s_axis_pfe_data=0x%0h", $time, s_axis_pfe_data);
            end

            if (pfe_csv_fd != 0) begin
                $fwrite(pfe_csv_fd, "%0t,%0d,%0d", $time, s_axis_pfe_voxel_x, s_axis_pfe_voxel_y);

                // pfe_i 从 10 递减到 0，打印出来的顺序刚好是 X, Y, Z, Intensity...
                for (pfe_i = EXPAND_PT_DIM - 1; pfe_i >= 0; pfe_i = pfe_i - 1) begin

                    if (pfe_i == 7) begin
                        // Q9.7 Intensity
                        pfe_q88_val = $itor($signed(s_axis_pfe_data[pfe_i*PT_WIDTH+:PT_WIDTH])) / 128.0;
                    end else if (pfe_i == 8 || pfe_i == 3 || pfe_i == 0) begin
                        // Q4.12 Z, Z-mean, Z-vcenter
                        pfe_q88_val = $itor($signed(s_axis_pfe_data[pfe_i*PT_WIDTH+:PT_WIDTH])) / 4096.0;
                    end else begin
                        // Q8.8 X, Y 及衍生坐标
                        pfe_q88_val = $itor($signed(s_axis_pfe_data[pfe_i*PT_WIDTH+:PT_WIDTH])) / 256.0;
                    end

                    $fwrite(pfe_csv_fd, ",%0.6f", pfe_q88_val);
                end
                $fwrite(pfe_csv_fd, "\n");
            end

            // === 点数统计逻辑 ===
            if (s_axis_pfe_last) begin
                out_pt_cnt <= pt_cnt + 1;
                pt_cnt     <= 0;
            end else begin
                pt_cnt <= pt_cnt + 1;
            end
        end
    end

    // Simulation log: output
    always @(posedge clk) begin
        if (rst_n && m_axis_out_valid) begin
            if (csv_fd != 0) begin
                // 将 out_pt_cnt 打印在第四列
                $fwrite(csv_fd, "%0t,%0d,%0d,%0d", $time, m_axis_out_voxel_x, m_axis_out_voxel_y, out_pt_cnt);
                for (out_i = 0; out_i < OUT_PT_DIM; out_i = out_i + 1) begin
                    out_q88_val = $itor($signed(m_axis_out_data[out_i*PT_WIDTH+:PT_WIDTH])) / 256.0;
                    $fwrite(csv_fd, ",%0.6f", out_q88_val);
                end
                $fwrite(csv_fd, "\n");
            end
        end
    end
`endif

endmodule
