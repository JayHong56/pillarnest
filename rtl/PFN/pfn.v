module pfn_layer #(
    parameter EXPAND_PT_DIM   = 11,
    parameter COORD_WIDTH     = 11,
    parameter OUT_PT_DIM      = 48,
    parameter PT_WIDTH        = 16,         // 输入数据位宽
    parameter MEM_WEIGHT_FILE = "NOTHING",
    parameter MEM_BIAS_FILE   = "NOTHING",
    parameter WEIGHT_WIDTH    = 16,         // 权重位宽 (通常量化为 INT8)
    parameter ACC_WIDTH       = 32          // 累加器位宽
) (
    input wire clk,
    input wire rst_n,

    // =======================================================
    // 新增 tready 信号，用于给前级 PFE 施加反压
    // 因为处理一个点需要 2 拍，上游不能每一拍都送新数据
    // =======================================================
    output wire s_axis_pfe_tready,
    input wire s_axis_pfe_valid,
    input wire [EXPAND_PT_DIM*PT_WIDTH-1:0] s_axis_pfe_data,  // Q8.8
    input wire s_axis_pfe_last,  // 指示该点是否为当前 Voxel 的最后一个点
    input wire s_axis_pfe_voxel_valid,
    input wire signed [COORD_WIDTH-1:0] s_axis_pfe_voxel_x,
    input wire signed [COORD_WIDTH-1:0] s_axis_pfe_voxel_y,


    // 最终池化后的输出
    output reg                                  m_axis_out_voxel_valid,
    output reg signed [        COORD_WIDTH-1:0] m_axis_out_voxel_x,
    output reg signed [        COORD_WIDTH-1:0] m_axis_out_voxel_y,
    output reg                                  m_axis_out_valid,
    output reg        [OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data,
    output wire                                 m_axis_out_data_bit      // 仅用于仿真观察输出数据
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
    // 时分复用控制与输入锁存
    // =======================================================
    reg phase;  // 0: 处理通道 0~23, 1: 处理通道 24~47
    assign s_axis_pfe_tready = (phase == 0);  // 只有 phase 0 才允许接收新数据

    // 在 phase 0 接收到数据时，锁存供 phase 1 使用
    reg [EXPAND_PT_DIM*PT_WIDTH-1:0] latched_pfe_data;
    reg latched_last;
    reg latched_voxel_valid;
    reg signed [COORD_WIDTH-1:0] latched_voxel_x;
    reg signed [COORD_WIDTH-1:0] latched_voxel_y;

    // 当前计算使用的数据流选择：0拍用输入线上的，1拍用锁存的
    wire [EXPAND_PT_DIM*PT_WIDTH-1:0] current_data = (phase == 0) ? s_axis_pfe_data : latched_pfe_data;

    // =======================================================
    // 硬件实例化: 仅需 24 组 MAC 和 ReLU，减少 50% DSP
    // =======================================================
    reg signed [ACC_WIDTH-1:0] mac_comb[0:HALF_OUT_DIM-1];
    reg [PT_WIDTH-1:0] relu_comb[0:HALF_OUT_DIM-1];
    reg signed [63:0] dequant_temp;  // 用于修复之前的编译 Bug

    integer j, k;
    always @(*) begin
        for (j = 0; j < HALF_OUT_DIM; j = j + 1) begin
            // 依据当前 phase 读取不同半区的 Bias 和 Weight
            mac_comb[j] = ($signed(bias_rom[phase?j+HALF_OUT_DIM : j]) <<< 8);
            for (k = 0; k < EXPAND_PT_DIM; k = k + 1) begin
                mac_comb[j] = mac_comb[j] + $signed(current_data[k*PT_WIDTH+:PT_WIDTH]) *
                    $signed(weight_row_rom[phase?j+HALF_OUT_DIM : j][k*WEIGHT_WIDTH+:WEIGHT_WIDTH]);
            end

            // 修复 Bug：在组合逻辑内部做反量化乘法
            dequant_temp = mac_comb[j] * 994;

            if (mac_comb[j] < 0) relu_comb[j] = 0;  // ReLU 激活
            else relu_comb[j] = dequant_temp[PT_WIDTH+20-1 : 20];  // 乘以994后右移20位
        end
    end

    // =======================================================
    // 时序更新逻辑: Max Pool 与 数据输出
    // =======================================================
    reg signed [PT_WIDTH-1:0] max_pool_regs[0:OUT_PT_DIM-1];
    integer oc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 1'b0;
            latched_last <= 1'b0;
            latched_voxel_valid <= 1'b0;
            latched_voxel_x <= {COORD_WIDTH{1'b0}};
            latched_voxel_y <= {COORD_WIDTH{1'b0}};
            latched_pfe_data <= 0;

            for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                max_pool_regs[oc] <= 0;
            end

            m_axis_out_valid <= 1'b0;
            m_axis_out_data <= 0;
            m_axis_out_voxel_valid <= 1'b0;
            m_axis_out_voxel_x <= {COORD_WIDTH{1'b0}};
            m_axis_out_voxel_y <= {COORD_WIDTH{1'b0}};
        end else begin
            // 默认 Valid 拉低，形成单周期脉冲
            m_axis_out_valid <= 1'b0;
            m_axis_out_voxel_valid <= 1'b0;

            if (phase == 0) begin
                // 【周期 1】收到有效输入，执行前半区 (0~23) 运算
                if (s_axis_pfe_valid) begin
                    // 锁存元数据给下一个周期使用
                    latched_pfe_data    <= s_axis_pfe_data;
                    latched_last        <= s_axis_pfe_last;
                    latched_voxel_valid <= s_axis_pfe_voxel_valid;
                    latched_voxel_x     <= s_axis_pfe_voxel_x;
                    latched_voxel_y     <= s_axis_pfe_voxel_y;

                    // 更新前半区 (0~23) 的 Max Pool
                    for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                        if (relu_comb[oc] > max_pool_regs[oc]) begin
                            max_pool_regs[oc] <= relu_comb[oc];
                        end
                    end

                    phase <= 1'b1;  // 切换到下半区计算
                end
            end else begin
                // 【周期 2】使用锁存数据，执行后半区 (24~47) 运算

                // 更新后半区 (24~47) 的 Max Pool
                for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                    if (relu_comb[oc] > max_pool_regs[oc+HALF_OUT_DIM]) begin
                        max_pool_regs[oc+HALF_OUT_DIM] <= relu_comb[oc];
                    end
                end

                // 如果是当前 Voxel 的最后一个点，结算并输出
                if (latched_last) begin
                    m_axis_out_valid       <= 1'b1;
                    m_axis_out_voxel_valid <= latched_voxel_valid;
                    m_axis_out_voxel_x     <= latched_voxel_x;
                    m_axis_out_voxel_y     <= latched_voxel_y;

                    for (oc = 0; oc < HALF_OUT_DIM; oc = oc + 1) begin
                        // 1. 组装前半区数据（由于上一拍已经写入 max_pool，直接取值）
                        m_axis_out_data[oc*PT_WIDTH+:PT_WIDTH] <= max_pool_regs[oc];

                        // 2. 组装后半区数据（当前拍正在更新，使用组合逻辑的三目运算符保证数据最新）
                        m_axis_out_data[(oc + HALF_OUT_DIM)*PT_WIDTH +: PT_WIDTH] <= 
                            (relu_comb[oc] > max_pool_regs[oc + HALF_OUT_DIM]) ? relu_comb[oc] : max_pool_regs[oc + HALF_OUT_DIM];

                        // 3. 输出后立刻清空寄存器，为下一个 Voxel 做准备
                        max_pool_regs[oc] <= 0;
                        max_pool_regs[oc+HALF_OUT_DIM] <= 0;
                    end
                end

                phase <= 1'b0;  // 一点处理完毕，回到空闲/接收状态
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
