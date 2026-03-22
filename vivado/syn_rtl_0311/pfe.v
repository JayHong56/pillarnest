module pfe #(
    parameter COORD_WIDTH = 11,
    parameter PT_WIDTH = 16,
    parameter HASH_ADDR_WIDTH = 8,  // 256
    parameter MAX_VOXEL_NUM = 12'd20,
    parameter VN_WIDTH = 5,
    parameter EXPAND_PT_DIM = 11,  // x,y,z,intensity,0,(x-mean,y-mean,z-mean,intensity-mean),(x-vmean,y-vmean,z-vmean,intensity-vmean)
    parameter BRAM_DATA_WIDTH = 256,  // 64bit * 【4 points per row】
    parameter BRAM_ADDR_WIDTH = 10  // 128pillar * 5brams
) (
    input  wire                                       clk,
    input  wire                                       rst_n,
    input  wire                                       s_axis_expire_tvalid,
    output wire                                       s_axis_expire_tready,
    input  wire [2*COORD_WIDTH+HASH_ADDR_WIDTH+5-1:0] s_axis_expire_tdata,   // NOTE
    output wire                                       bram_clk_b,
    output wire                                       bram_rst_b,
    output reg  [                BRAM_ADDR_WIDTH-1:0] bram_addr_b,           // 假设地址空间足够大
    output reg                                        bram_en_b,
    input  wire [                BRAM_DATA_WIDTH-1:0] bram_rdata_b,          // 255:0 ((9+7)*4 )*4points
    output reg                                        m_axis_pfe_valid,
    output reg  [         EXPAND_PT_DIM*PT_WIDTH-1:0] m_axis_pfe_data,       // 11*16 bits
    output reg                                        m_axis_pfe_last

);
    assign bram_clk_b = clk;
    assign bram_rst_b = ~rst_n;
    // 注意：Verilog 切片最好用固定数值，或者确保 parameter 计算正确
    wire signed [COORD_WIDTH-1:0] axis_voxel_x = s_axis_expire_tdata[2*COORD_WIDTH+HASH_ADDR_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire signed [COORD_WIDTH-1:0] axis_voxel_y = s_axis_expire_tdata[COORD_WIDTH+HASH_ADDR_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire [HASH_ADDR_WIDTH-1:0] axis_bram_index = s_axis_expire_tdata[HASH_ADDR_WIDTH+VN_WIDTH-1-:HASH_ADDR_WIDTH];
    wire [VN_WIDTH-1:0] axis_point_num_indicator = s_axis_expire_tdata[VN_WIDTH-1 : 0];  // 1-20 points

    // -----------------------------------------------------------
    // 2. 内部存储 (Points Buffer) & 累加器
    // -----------------------------------------------------------
    // 存储该 Voxel 内的所有点，供后续处理 (Process 阶段) 使用
    localparam EXPAND_VOXEL_ROW = MAX_VOXEL_NUM >> 2;  // 20 / 4 = 5
    localparam integer PT_WIDTH_I = 7;
    localparam integer PT_WIDTH_F = 9;


    // --------------------扩展voxel_center点坐标维度---------------------
    // voxel_x_fix16 = voxel_x * 0.15 - 54.0 + 0.075
    localparam signed [18-1:0] COEFF_SLOPE = 18'sd9830;  // 0.15
    localparam signed [23-1:0] COEFF_OFFSET = 23'sd3538944;  // 54.0

    // -----------------------------------------------------------
    // 源头安全反压控制 (In-flight tracking)
    // -----------------------------------------------------------
    reg serialize_busy;
    reg [2:0] inflight_cnt;

    wire fire_in;
    wire voxel_finished_pipe;  // 提前声明

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inflight_cnt <= 3'd0;
        end else begin
            case ({
                fire_in, voxel_finished_pipe
            })
                2'b10:   inflight_cnt <= inflight_cnt + 1'b1;  // 流水线进一个
                2'b01:   inflight_cnt <= inflight_cnt - 1'b1;  // 流水线出一个
                default: inflight_cnt <= inflight_cnt;
            endcase
        end
    end

    // 如果后级在吐数据，或者流水线里有数据在跑，就反压源头
    wire pipe_stall = serialize_busy || (inflight_cnt > 0);


    // 常用循环变量
    integer k, i;
    // Stage 1: 地址生成流水线 (Address Generation) 【5 cycles】
    reg  [2:0] req_phase;  // 0, 1, 2, 3, 4 循环 (3bits)
    reg        req_valid;  // 当前是否有 Voxel 在输入端

    // 握手逻辑：只有当 phase 归零且未被反压时才接收新 Voxel
    wire       ready_to_accept = (req_phase == 3'd0) && !pipe_stall;
    assign s_axis_expire_tready = ready_to_accept;
    assign fire_in = s_axis_expire_tvalid && ready_to_accept;

    // 锁存输入元数据 (随流水线流动)
    reg [VN_WIDTH-1:0] st1_point_num;
    reg [COORD_WIDTH-1:0] st1_voxel_x, st1_voxel_y;
    reg [HASH_ADDR_WIDTH-1:0] st1_bram_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_phase   <= 3'd0;
            req_valid   <= 1'b0;
            bram_en_b   <= 0;
            bram_addr_b <= 0;
        end else begin
            if (fire_in || req_phase != 0) begin
                if (req_phase == 0) begin
                    st1_point_num  <= axis_point_num_indicator;
                    st1_voxel_x    <= axis_voxel_x;
                    st1_voxel_y    <= axis_voxel_y;
                    st1_bram_index <= axis_bram_index;
                end

                bram_en_b <= 1'b1;
                bram_addr_b <= (req_phase == 0) ? ({axis_bram_index * EXPAND_VOXEL_ROW} + req_phase) 
                                                : ({st1_bram_index * EXPAND_VOXEL_ROW} + req_phase);

                req_phase <= (req_phase == 3'd4) ? 3'd0 : req_phase + 1'b1;
                req_valid <= 1'b1;
            end else begin
                req_valid <= 1'b0;
                bram_en_b <= 0;
            end
        end
    end

    // 将 Phase 和 Valid 信号随 BRAM 的 2 周期读取延迟进行打拍
    reg [         2:0] pipe_phase[0:2];  // 延迟 2 拍的 phase (3bits)
    reg                pipe_valid[0:2];  // 延迟 2 拍的 valid

    reg [VN_WIDTH-1:0] pipe_pnum [0:2];  // 元数据伴随流动
    reg [COORD_WIDTH-1:0] pipe_vx[0:2], pipe_vy[0:2];

    always @(posedge clk) begin
        pipe_phase[0] <= req_phase;
        pipe_phase[1] <= pipe_phase[0];
        pipe_phase[2] <= pipe_phase[1];
        pipe_valid[0] <= req_valid;
        pipe_valid[1] <= pipe_valid[0];
        pipe_valid[2] <= pipe_valid[1];

        pipe_pnum[0]  <= st1_point_num;
        pipe_pnum[1]  <= pipe_pnum[0];
        pipe_pnum[2]  <= pipe_pnum[1];
        pipe_vx[0]    <= st1_voxel_x;
        pipe_vx[1]    <= pipe_vx[0];
        pipe_vx[2]    <= pipe_vx[1];
        pipe_vy[0]    <= st1_voxel_y;
        pipe_vy[1]    <= pipe_vy[0];
        pipe_vy[2]    <= pipe_vy[1];
    end


    // Stage 2: 接收数据与累加 (Fetch & Accumulate)
    reg [4*PT_WIDTH-1:0] st2_points_buffer[0:MAX_VOXEL_NUM-1];
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_x_acc, sum_y_acc, sum_z_acc;

    wire [         2:0] cur_phase = pipe_phase[1];  // req_phase 已经打了两拍，正好在 BRAM 数据可用的这一拍
    wire                cur_valid = pipe_valid[1];
    wire [VN_WIDTH-1:0] cur_pnum = pipe_pnum[1];

    reg  [         4:0] base_idx;
    reg  [        63:0] cur_point_data;
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_x_step, sum_y_step, sum_z_step;
    // NOTE: Adder-Tree Type
    always @(posedge clk) begin
        if (cur_valid) begin
            // 单口每次只读 1 行 (4 个点), idx 为 0, 4, 8, 12, 16
            base_idx   = {cur_phase, 2'b00};
            sum_x_step = 0;
            sum_y_step = 0;
            sum_z_step = 0;

            for (k = 0; k < 4; k = k + 1) begin  // 一次只处理一行(4个点)
                if (base_idx + k < cur_pnum) begin
                    cur_point_data = bram_rdata_b[k*64+:64];
                    
                    st2_points_buffer[base_idx+k] <= cur_point_data;

                    sum_x_step = sum_x_step + $signed(cur_point_data[63-:16]);
                    sum_y_step = sum_y_step + $signed(cur_point_data[47-:16]);
                    sum_z_step = sum_z_step + $signed(cur_point_data[31-:16]);
                end
            end

            if (cur_phase == 0) begin
                sum_x_acc <= sum_x_step;
                sum_y_acc <= sum_y_step;
                sum_z_acc <= sum_z_step;
            end else begin
                sum_x_acc <= sum_x_acc + sum_x_step;
                sum_y_acc <= sum_y_acc + sum_y_step;
                sum_z_acc <= sum_z_acc + sum_z_step;
            end
        end
    end

    // Stage 3: 数据对齐与准备 (等待均值计算前置)
    // 目标：当 Stage 2 最后一个 Phase 完成后，锁存完整数据，准备喂给 DSP
    reg st3_valid;
    reg [VN_WIDTH-1:0] st3_pnum;
    reg [63:0] st3_points_buffer[0:MAX_VOXEL_NUM-1];
    reg signed [PT_WIDTH+VN_WIDTH-1:0] st3_sum_x, st3_sum_y, st3_sum_z;
    reg signed [COORD_WIDTH-1:0] st3_vx, st3_vy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) st3_valid <= 1'b0;
        else begin
            // 当流水线延迟达到 pipe_phase[2] == 4 时，说明 5 行数据已完全读完写完
            if (pipe_valid[2] && pipe_phase[2] == 3'd4) begin
                st3_valid <= 1'b1;
                st3_pnum  <= pipe_pnum[2];
                st3_sum_x <= sum_x_acc;
                st3_sum_y <= sum_y_acc;
                st3_sum_z <= sum_z_acc;
                st3_vx    <= pipe_vx[2];
                st3_vy    <= pipe_vy[2];

                for (i = 0; i < MAX_VOXEL_NUM; i = i + 1) begin
                    st3_points_buffer[i] <= st2_points_buffer[i];
                end
            end else begin
                st3_valid <= 1'b0;
            end
        end
    end

    // DSP 计算区 (纯组合逻辑 + 专用乘法器)
    reg signed [1+17-1:0] st3_reciprocal;  // 1.0 * 65536
    always @(*) begin
        case (st3_pnum)
            5'd1: st3_reciprocal = 18'd65536;
            5'd2: st3_reciprocal = 18'd32768;
            5'd3: st3_reciprocal = 18'd21845;
            5'd4: st3_reciprocal = 18'd16384;
            5'd5: st3_reciprocal = 18'd13107;
            5'd6: st3_reciprocal = 18'd10923;
            5'd7: st3_reciprocal = 18'd9362;
            5'd8: st3_reciprocal = 18'd8192;
            5'd9: st3_reciprocal = 18'd7282;
            5'd10: st3_reciprocal = 18'd6554;
            5'd11: st3_reciprocal = 18'd5958;
            5'd12: st3_reciprocal = 18'd5461;
            5'd13: st3_reciprocal = 18'd5041;
            5'd14: st3_reciprocal = 18'd4681;
            5'd15: st3_reciprocal = 18'd4369;
            5'd16: st3_reciprocal = 18'd4096;
            5'd17: st3_reciprocal = 18'd3855;
            5'd18: st3_reciprocal = 18'd3641;
            5'd19: st3_reciprocal = 18'd3449;
            5'd20: st3_reciprocal = 18'd3277;
            default: st3_reciprocal = 18'd0;
        endcase
    end

    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_x;
    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_y;
    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_z;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_mult_voxel_x;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_mult_voxel_y;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_sub_voxel_x;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_sub_voxel_y;

    assign temp_sub_voxel_x = temp_mult_voxel_x - COEFF_OFFSET;  // 注意位宽防止溢出
    assign temp_sub_voxel_y = temp_mult_voxel_y - COEFF_OFFSET;
    // Cluster Center
    fxp_mul #(
        .WIIA (PT_WIDTH_I + VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_x (
        .ina     (st3_sum_x),
        .inb     (st3_reciprocal),
        .out     (temp_mult_x),
        .overflow()
    );
    fxp_mul #(
        .WIIA (PT_WIDTH_I + VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_y (
        .ina     (st3_sum_y),
        .inb     (st3_reciprocal),
        .out     (temp_mult_y),
        .overflow()
    );
    fxp_mul #(
        .WIIA (PT_WIDTH_I + VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_z (
        .ina     (st3_sum_z),
        .inb     (st3_reciprocal),
        .out     (temp_mult_z),
        .overflow()
    );
    // Voxel Center
    fxp_mul #(
        .WIIA (COORD_WIDTH),
        .WIFA (0),
        .WIIB (18),
        .WIFB (0),
        .WOI  (29),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_vx (
        .ina     (st3_vx),
        .inb     (COEFF_SLOPE),
        .out     (temp_mult_voxel_x),
        .overflow()
    );
    fxp_mul #(
        .WIIA (COORD_WIDTH),
        .WIFA (0),
        .WIIB (18),
        .WIFB (0),
        .WOI  (29),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_vy (
        .ina     (st3_vy),
        .inb     (COEFF_SLOPE),
        .out     (temp_mult_voxel_y),
        .overflow()
    );

    // Stage 4: 结果打拍与隔离 (扇出控制核心)
    reg st4_valid;
    reg [VN_WIDTH-1:0] st4_pnum;
    reg [63:0] st4_points_buffer[0:MAX_VOXEL_NUM-1];
    reg signed [PT_WIDTH-1:0] st4_mean_x, st4_mean_y, st4_mean_z;
    reg signed [PT_WIDTH-1:0] st4_vx_fix16, st4_vy_fix16, st4_vz_fix16;
    assign voxel_finished_pipe = st4_valid;  // 供反压计数的信号
    always @(posedge clk) begin
        st4_valid <= st3_valid;
        if (st3_valid) begin
            st4_pnum <= st3_pnum;
            // 截取定点数输出
            // Sum * (1/N) >> 16
            // 注意：sum 是带符号的，reciprocal 是无符号的
            st4_mean_x <= temp_mult_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
            st4_mean_y <= temp_mult_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
            st4_mean_z <= temp_mult_z[16-PT_WIDTH_F+15:16-PT_WIDTH_F];

            st4_vx_fix16 <= temp_sub_voxel_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
            st4_vy_fix16 <= temp_sub_voxel_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
            st4_vz_fix16 <= 16'hfe00;  // -1.0 Q7.9

            for (i = 0; i < MAX_VOXEL_NUM; i = i + 1) begin
                st4_points_buffer[i] <= st3_points_buffer[i];
            end
        end
    end

    // Stage 5: 特征扩维与最终输出 (Feature Expansion)
    // 输出寄存器
    reg [EXPAND_PT_DIM*PT_WIDTH-1:0] expanded_points_buffer[0:MAX_VOXEL_NUM-1];  // 20*[11*16]
    reg st5_valid;
    reg [VN_WIDTH-1:0] st5_pnum;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st5_valid <= 1'b0;
            st5_pnum  <= {VN_WIDTH{1'b0}};
        end else begin
            st5_valid <= st4_valid;

            if (st4_valid) begin
                st5_pnum <= st4_pnum;

                for (i = 0; i < MAX_VOXEL_NUM; i = i + 1) begin
                    if (i < st4_pnum) begin
                        expanded_points_buffer[i] <= {
                            st4_points_buffer[i][63-:16],
                            st4_points_buffer[i][47-:16],
                            st4_points_buffer[i][31-:16],
                            st4_points_buffer[i][15-:16],
                            16'd0,
                            $signed(st4_points_buffer[i][63-:16]) - st4_mean_x,
                            $signed(st4_points_buffer[i][47-:16]) - st4_mean_y,
                            $signed(st4_points_buffer[i][31-:16]) - st4_mean_z,
                            $signed(st4_points_buffer[i][63-:16]) - st4_vx_fix16,
                            $signed(st4_points_buffer[i][47-:16]) - st4_vy_fix16,
                            $signed(st4_points_buffer[i][31-:16]) - st4_vz_fix16
                        };
                    end else begin
                        expanded_points_buffer[i] <= 0;
                    end
                end
            end
        end
    end

    // Stage 6: 过渡序列化状态机 (Serialization FSM)
    // 目标：将并行的 expanded_points_buffer 逐个发送给 pfn_layer
    reg [VN_WIDTH-1:0] point_cnt;
    reg [VN_WIDTH-1:0] latched_pnum;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serialize_busy   <= 1'b0;
            point_cnt        <= 0;
            latched_pnum     <= 0;

            m_axis_pfe_valid <= 1'b0;
            m_axis_pfe_data  <= 0;
            m_axis_pfe_last  <= 1'b0;
        end else begin
            // 默认拉低单周期脉冲信号
            m_axis_pfe_valid <= 1'b0;
            m_axis_pfe_last  <= 1'b0;

            if (!serialize_busy) begin
                // 空闲状态：等待 Stage 5 送来新的有效 Voxel
                // 注意：这里的 m_axis_pfe_valid 是你原来 Stage 5 产生的那个信号
                if (st5_valid) begin
                    latched_pnum <= st5_pnum;  // 锁存当前 Voxel 的有效点数

                    // 异常保护：只有当有效点数 > 0 时才启动发送
                    if (st5_pnum > 0) begin
                        serialize_busy   <= 1'b1;
                        m_axis_pfe_valid <= 1'b1;
                        // 立刻发出当前 Voxel 的第 1 个点 (index = 0)
                        m_axis_pfe_data  <= expanded_points_buffer[0];

                        if (st5_pnum == 5'd1) begin
                            // 如果这个 Voxel 只有 1 个点，发完立刻结束
                            m_axis_pfe_last <= 1'b1;
                            serialize_busy  <= 1'b0;
                        end else begin
                            // 准备在下一个周期发第 2 个点 (index = 1)
                            point_cnt <= 5'd1;
                        end
                    end
                end
            end else begin
                // 发送状态：依次发出剩余的点
                m_axis_pfe_valid <= 1'b1;
                m_axis_pfe_data  <= expanded_points_buffer[point_cnt];

                if (point_cnt == latched_pnum - 1) begin
                    // 已经是最后一个点了
                    m_axis_pfe_last <= 1'b1;
                    serialize_busy  <= 1'b0;  // 发完收工，回到空闲状态
                end else begin
                    point_cnt <= point_cnt + 1'b1;
                end
            end
        end
    end
endmodule

