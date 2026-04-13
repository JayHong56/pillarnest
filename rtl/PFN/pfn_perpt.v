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
    input  wire                                     s_axis_pfe_flush_done,
    // output
    output reg                                      m_axis_out_voxel_valid,
    output reg signed  [           COORD_WIDTH-1:0] m_axis_out_voxel_x,
    output reg signed  [           COORD_WIDTH-1:0] m_axis_out_voxel_y,
    output reg                                      m_axis_out_valid,
    input  wire                                     m_axis_out_tready,
    output reg         [   OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data,
    output wire                                     m_axis_out_flush_done
);

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
    // 修复：乘法器操作数提前 Mux，强制复用 DSP 硬件
    // =======================================================
    reg phase;  // 0: 处理通道 0~23, 1: 处理通道 24~47
    assign s_axis_pfe_tready = (phase == 0);

    // 输入数据的第一级元数据锁存
    reg        [EXPAND_PT_DIM*PT_WIDTH-1:0] latched_pfe_data;
    reg                                     latched_last;
    reg                                     latched_voxel_valid;
    reg signed [           COORD_WIDTH-1:0] latched_voxel_x;
    reg signed [           COORD_WIDTH-1:0] latched_voxel_y;

    // 伴随数据向下游流动的控制信号
    reg                                     st2_valid;
    reg                                     st2_phase;
    reg                                     st2_last;
    reg                                     st2_voxel_valid;
    reg signed [           COORD_WIDTH-1:0] st2_voxel_x;
    reg signed [           COORD_WIDTH-1:0] st2_voxel_y;

    // --- 核心修改：新增组合逻辑 Mux 提取操作数 ---
    reg signed [              PT_WIDTH-1:0] op_data             [0:EXPAND_PT_DIM-1];
    reg signed [          WEIGHT_WIDTH-1:0] op_weight           [ 0:HALF_OUT_DIM-1] [0:EXPAND_PT_DIM-1];
    reg signed [             ACC_WIDTH-1:0] op_bias             [ 0:HALF_OUT_DIM-1];

    integer i_k, i_j;  // 组合逻辑专用循环变量
    always @(*) begin
        // 1. Mux 选择乘法器的 数据输入 (11个维度)
        for (i_k = 0; i_k < EXPAND_PT_DIM; i_k = i_k + 1) begin
            op_data[i_k] = (phase == 0) ? $signed(s_axis_pfe_data[i_k*PT_WIDTH+:PT_WIDTH]) :
                $signed(latched_pfe_data[i_k*PT_WIDTH+:PT_WIDTH]);
        end

        // 2. Mux 选择乘法器的 权重输入 和 加法器的 Bias 输入 (24个输出通道)
        for (i_j = 0; i_j < HALF_OUT_DIM; i_j = i_j + 1) begin
            op_bias[i_j] = (phase == 0) ? ($signed(bias_rom[i_j]) <<< 8) : ($signed(bias_rom[i_j+HALF_OUT_DIM]) <<< 8);

            for (i_k = 0; i_k < EXPAND_PT_DIM; i_k = i_k + 1) begin
                op_weight[i_j][i_k] = (phase == 0) ? $signed(weight_row_rom[i_j][i_k*WEIGHT_WIDTH+:WEIGHT_WIDTH]) :
                    $signed(weight_row_rom[i_j+HALF_OUT_DIM][i_k*WEIGHT_WIDTH+:WEIGHT_WIDTH]);
            end
        end
    end

    // --- 核心流水线寄存器 (Pipeline Registers) ---
    // 添加综合属性：强制要求 Vivado 将此数组映射为 DSP48 的内部寄存器
    (* use_dsp = "yes" *)reg signed [ACC_WIDTH-1:0] st2_mult[0:HALF_OUT_DIM-1] [0:EXPAND_PT_DIM-1];
    reg signed [ACC_WIDTH-1:0] st2_bias[0:HALF_OUT_DIM-1];

    integer j, k;  // 时序逻辑专用循环变量
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

                    // 传递控制信号
                    st2_valid           <= 1'b1;
                    st2_phase           <= 1'b0;
                    st2_last            <= s_axis_pfe_last;
                    st2_voxel_valid     <= s_axis_pfe_voxel_valid;
                    st2_voxel_x         <= s_axis_pfe_voxel_x;
                    st2_voxel_y         <= s_axis_pfe_voxel_y;

                    // --- 统一乘法运算：硬件将被完美复用 ---
                    for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                        st2_bias[j] <= op_bias[j];
                        for (k = 0; k < EXPAND_PT_DIM; k = k + 1) begin
                            st2_mult[j][k] <= op_data[k] * op_weight[j][k];
                        end
                    end
                end else begin
                    st2_valid <= 1'b0;
                end
            end else begin
                // phase == 1 时
                phase           <= 1'b0;  // 一点处理完毕，回到接收新点状态

                // 传递控制信号
                st2_valid       <= 1'b1;
                st2_phase       <= 1'b1;
                st2_last        <= latched_last;
                st2_voxel_valid <= latched_voxel_valid;
                st2_voxel_x     <= latched_voxel_x;
                st2_voxel_y     <= latched_voxel_y;

                // --- 统一乘法运算：这里代码和 Phase 0 完全一致！ ---
                // Vivado 会识别出它与 Phase 0 共享了同一个算术单元，只会生成 24x11 个乘法器
                for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                    st2_bias[j] <= op_bias[j];
                    for (k = 0; k < EXPAND_PT_DIM; k = k + 1) begin
                        st2_mult[j][k] <= op_data[k] * op_weight[j][k];
                    end
                end
            end
        end
    end

    // =======================================================
    // 级联流水线 Stage 2: 强制加法树 (打一拍，寄存器命名为 st3)
    // 目标：将乘法结果求和，并锁存到寄存器，斩断时序长路径
    // =======================================================
    // 伴随数据向下游流动的 st3 控制信号
    reg st3_valid;
    reg st3_phase;
    reg st3_last;
    reg st3_voxel_valid;
    reg signed [COORD_WIDTH-1:0] st3_voxel_x;
    reg signed [COORD_WIDTH-1:0] st3_voxel_y;

    // 核心数据寄存器：存放加法树结果
    reg signed [ACC_WIDTH-1:0] st3_mac_tree[0:HALF_OUT_DIM-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st3_valid       <= 1'b0;
            st3_phase       <= 1'b0;
            st3_last        <= 1'b0;
            st3_voxel_valid <= 1'b0;
            st3_voxel_x     <= {COORD_WIDTH{1'b0}};
            st3_voxel_y     <= {COORD_WIDTH{1'b0}};
            for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                st3_mac_tree[j] <= 0;
            end
        end else begin
            // 1. 无脑传递控制信号 (把 st2 的状态向后推一拍)
            st3_valid       <= st2_valid;
            st3_phase       <= st2_phase;
            st3_last        <= st2_last;
            st3_voxel_valid <= st2_voxel_valid;
            st3_voxel_x     <= st2_voxel_x;
            st3_voxel_y     <= st2_voxel_y;

            // 2. 数据计算：当有有效数据时，计算 4 级加法树并打入寄存器
            if (st2_valid) begin
                for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
                    st3_mac_tree[j] <= (
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
                end
            end
        end
    end
    // =======================================================
    // 级联流水线 Stage 3: 去量化与 ReLU (纯组合逻辑)
    // 数据源变为刚刚打过拍的 st3_mac_tree
    // =======================================================
    reg [PT_WIDTH-1:0] relu_comb[0:HALF_OUT_DIM-1];
    reg signed [63:0] dequant_temp[0:HALF_OUT_DIM-1];

    always @(*) begin
        for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
            // 反量化乘法 (使用打过拍的数据 st3_mac_tree)
            dequant_temp[j] = st3_mac_tree[j] * 994;

            // ReLU
            if (st3_mac_tree[j] < 0) relu_comb[j] = 0;
            else relu_comb[j] = dequant_temp[j][PT_WIDTH+20-1 : 20];
        end
    end

    // =======================================================
    // 级联流水线 Stage 4: Max Pool 与 数据输出
    // 这里的控制条件全部改为监听 st3 的信号
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

            // 注意：这里改为由 st3_valid 触发
            if (st3_valid) begin
                if (st3_phase == 0) begin
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
                    // 注意：这里改为看 st3_last
                    if (st3_last) begin
                        m_axis_out_valid       <= 1'b1;
                        m_axis_out_voxel_valid <= st3_voxel_valid;
                        m_axis_out_voxel_x     <= st3_voxel_x;
                        m_axis_out_voxel_y     <= st3_voxel_y;

                        for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                            // 1. 前半区数据直接从 max_pool_regs 取出
                            m_axis_out_data[oc*PT_WIDTH+:PT_WIDTH] <= max_pool_regs[oc];

                            // 2. 后半区数据：用三目运算符挑出最大值抢时间输出
                            m_axis_out_data[(oc + HALF_OUT_DIM)*PT_WIDTH +: PT_WIDTH] <= 
                                (relu_comb[oc] > max_pool_regs[oc + HALF_OUT_DIM]) ? relu_comb[oc] : max_pool_regs[oc + HALF_OUT_DIM];

                            // 3. 结算完毕，清空该 Voxel 的所有缓存池
                            max_pool_regs[oc] <= 0;
                            max_pool_regs[oc+HALF_OUT_DIM] <= 0;
                        end
                    end
                end
            end
        end
    end


    // =========================================================================
    // 帧尾排空信号传递 (Flush Propagation)
    // =========================================================================
    reg  pfn_flushing_req;
    reg  m_axis_out_flush_done_reg;

    // PFN 完全排空的条件：
    // 1. phase == 0 : 没有正在等待处理后半通道 24~47 的挂起点
    // 2. !st2_valid && !st3_valid : 内部加法树寄存器中无数据
    // 3. !m_axis_out_valid : 最终输出结果已被弹出
    wire pfn_empty = (phase == 1'b0) && !st2_valid && !st3_valid && !m_axis_out_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pfn_flushing_req          <= 1'b0;
            m_axis_out_flush_done_reg <= 1'b0;
        end else begin
            // 捕获 PFE 传来的帧结束标志
            if (s_axis_pfe_flush_done) begin
                pfn_flushing_req <= 1'b1;
            end

            // 等待加法树运算结束，结果输出后，再把 flush_done 继续往下传
            if (pfn_flushing_req && pfn_empty && !m_axis_out_flush_done_reg) begin
                m_axis_out_flush_done_reg <= 1'b1;
                pfn_flushing_req          <= 1'b0;
            end else begin
                m_axis_out_flush_done_reg <= 1'b0;
            end
        end
    end

    assign m_axis_out_flush_done = m_axis_out_flush_done_reg;


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
