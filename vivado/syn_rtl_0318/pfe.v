module pfe #(
    parameter COORD_WIDTH = 11,
    parameter PT_WIDTH = 16,
    // parameter HASH_ADDR_WIDTH = 8,  // 256
    parameter MAX_VOXEL_NUM = 12'd20,
    parameter VN_WIDTH = 5,
    parameter EXPAND_PT_DIM = 11,  // x,y,z,intensity,0,(x-mean,y-mean,z-mean,intensity-mean),(x-vmean,y-vmean,z-vmean,intensity-vmean)
    parameter BRAM_DATA_WIDTH = 640,  // 64bit * 【10 points per row】
    parameter BRAM_ADDR_WIDTH = 9  // 256pillar * 2brams
) (
    input  wire                                              clk,
    input  wire                                              rst_n,
    input  wire                                              s_axis_expire_tvalid,
    output wire                                              s_axis_expire_tready,
    input  wire [2*COORD_WIDTH+BRAM_ADDR_WIDTH+VN_WIDTH-1:0] s_axis_expire_tdata,   // NOTE
    output wire                                              bram_pfe_clk,
    // output wire                                       bram_pfe_rst,
    output reg  [                       BRAM_ADDR_WIDTH-1:0] bram_pfe_addr,         // 假设地址空间足够大
    // output reg                                        bram_pfe_en,
    input  wire [                       BRAM_DATA_WIDTH-1:0] bram_pfe_rdata,        // 255:0 ((9+7)*4 )*4points
    output reg                                               m_axis_pfe_valid,
    output reg  [                EXPAND_PT_DIM*PT_WIDTH-1:0] m_axis_pfe_data,       // 11*16 bits
    output reg                                               m_axis_pfe_last

);
    assign bram_pfe_clk = clk;
    // 注意：Verilog 切片最好用固定数值，或者确保 parameter 计算正确
    wire signed [COORD_WIDTH-1:0] axis_voxel_x = s_axis_expire_tdata[2*COORD_WIDTH+BRAM_ADDR_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire signed [COORD_WIDTH-1:0] axis_voxel_y = s_axis_expire_tdata[COORD_WIDTH+BRAM_ADDR_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire [BRAM_ADDR_WIDTH-1:0] axis_bram_index = s_axis_expire_tdata[BRAM_ADDR_WIDTH+VN_WIDTH-1-:BRAM_ADDR_WIDTH];
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
    reg  [2:0] inflight_cnt;
    wire       fire_in;

    // Stage2 完成一个 voxel，并成功写入 Stage3
    wire       st2_to_st3;

    // 统一的容量模型：
    // inflight_cnt  : Stage1/2 中已经接收、但还没落到 Stage3 的 voxel 数
    // 总容量 = VOX_FIFO_DEPTH + 2
    wire       pipe_stall;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inflight_cnt <= 3'd0;
        end else begin
            case ({
                fire_in, st2_to_st3
            })
                2'b10:   inflight_cnt <= inflight_cnt + 1'b1;  // 新 voxel 进入 Stage1/2
                2'b01:   inflight_cnt <= inflight_cnt - 1'b1;  // 一个 voxel 落入 Stage3
                default: inflight_cnt <= inflight_cnt;
            endcase
        end
    end


    // 常用循环变量
    integer k, i;
    // Stage 1: 地址生成流水线 (Address Generation) 【2 cycles】
    reg  [2:0] req_phase;
    reg        req_valid;
    wire       ready_to_accept = (req_phase == 3'd0) && !pipe_stall;
    assign s_axis_expire_tready = ready_to_accept;
    assign fire_in = s_axis_expire_tvalid && ready_to_accept;

    reg [VN_WIDTH-1:0] st1_point_num;
    reg [COORD_WIDTH-1:0] st1_voxel_x, st1_voxel_y;
    reg [BRAM_ADDR_WIDTH-1:0] st1_bram_b_addr;  // 这里换成记录基准地址
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_phase <= 3'd0;
            req_valid <= 1'b0;
            bram_pfe_addr <= 0;
        end else begin
            if (fire_in || req_phase != 0) begin
                if (req_phase == 0) begin
                    st1_point_num   <= axis_point_num_indicator;
                    st1_voxel_x     <= axis_voxel_x;
                    st1_voxel_y     <= axis_voxel_y;
                    st1_bram_b_addr <= axis_bram_index;  // 锁存 base_addr
                end

                bram_pfe_addr <= (req_phase == 0) ? (axis_bram_index) : (st1_bram_b_addr + 1'b1);
                req_phase <= (req_phase == 3'd1) ? 3'd0 : req_phase + 1'b1;
                req_valid <= 1'b1;
            end else begin
                req_valid <= 1'b0;
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
    wire [         2:0] cur_phase = pipe_phase[1];
    wire                cur_valid = pipe_valid[1];
    wire [VN_WIDTH-1:0] cur_pnum = pipe_pnum[1];
    reg  [         4:0] base_idx;
    reg  [        63:0] cur_point_data;
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_x_step, sum_y_step, sum_z_step;
    // NOTE: Adder-Tree Type
    always @(posedge clk) begin
        if (cur_valid) begin
            // phase 0 时读取前 10 个点 (idx 0~9)，phase 1 时读取后 10 个点 (idx 10~19)
            base_idx   = (cur_phase == 3'd0) ? 5'd0 : 5'd10;
            sum_x_step = 0;
            sum_y_step = 0;
            sum_z_step = 0;

            for (k = 0; k < 10; k = k + 1) begin
                if (base_idx + k < cur_pnum) begin
                    // 从 640 bits 的 BRAM 数据中截取对应的 64 bits 点数据
                    cur_point_data = bram_pfe_rdata[k*64+:64];

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
    // Stage 2 -> Stage 3 完成条件：当前 voxel 两行数据都读完
    wire st2_valid = pipe_valid[2] && (pipe_phase[2] == 3'd1);
    reg  st3_valid;
    reg  st4_valid;
    wire st4_push;
    wire st4_ready_for_new = !st4_valid || st4_push;

    // Stage3 本拍是否会向 Stage4 前进
    wire st3_to_st4 = st3_valid && st4_ready_for_new;

    // Stage3 本拍是否能接收新的 Stage2 输出：
    // - st3 当前空
    // - 或者 st3 当前有效，但本拍会前推给 Stage4
    wire st3_ready_for_s2 = !st3_valid || st3_to_st4;

    // 只有真正写进 Stage3，才算 Stage1/2 里的 inflight voxel “落地”
    assign st2_to_st3 = st2_valid && st3_ready_for_s2;

    reg [VN_WIDTH-1:0] st3_pnum;
    reg [63:0] st3_points_buffer[0:MAX_VOXEL_NUM-1];
    reg signed [PT_WIDTH+VN_WIDTH-1:0] st3_sum_x, st3_sum_y, st3_sum_z;
    reg signed [COORD_WIDTH-1:0] st3_vx, st3_vy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st3_valid <= 1'b0;
        end else begin
            // 优先处理“写入新的 Stage3 数据”
            // 如果 st3_to_st4 与 st2_valid 同拍成立，就相当于 Stage3 无缝换包
            if (st2_to_st3) begin
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
            end else if (st3_to_st4) begin
                // Stage3 数据前推到 Stage4，本拍自己清空
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
    reg [VN_WIDTH-1:0] st4_pnum;
    reg [63:0] st4_points_buffer[0:MAX_VOXEL_NUM-1];
    reg signed [PT_WIDTH-1:0] st4_mean_x, st4_mean_y, st4_mean_z;
    reg signed [PT_WIDTH-1:0] st4_vx_fix16, st4_vy_fix16, st4_vz_fix16;

    // Stage4 -> FIFO：只有 FIFO 不满才能 push
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st4_valid <= 1'b0;
        end else begin
            // 本拍 Stage3 -> Stage4
            if (st3_to_st4) begin
                st4_valid <= 1'b1;
                st4_pnum <= st3_pnum;

                st4_mean_x <= temp_mult_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                st4_mean_y <= temp_mult_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                st4_mean_z <= temp_mult_z[16-PT_WIDTH_F+15:16-PT_WIDTH_F];

                st4_vx_fix16 <= temp_sub_voxel_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                st4_vy_fix16 <= temp_sub_voxel_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                st4_vz_fix16 <= 16'hfe00;  // -1.0 Q7.9

                for (i = 0; i < MAX_VOXEL_NUM; i = i + 1) begin
                    st4_points_buffer[i] <= st3_points_buffer[i];
                end

            end else if (st4_push) begin
                // 仅 push，没有新的 st3 数据顶进来，则清空 Stage4
                st4_valid <= 1'b0;
            end
        end
    end


    // =========================================================================
    // 重构的 Stage 5: 4-entry Voxel FIFO
    // 每个 entry 存一个完整 voxel 的展开结果
    // =========================================================================
    localparam VOX_FIFO_DEPTH = 4;
    localparam VOX_FIFO_AW = 2;  // log2(4)=2

    reg  [EXPAND_PT_DIM*PT_WIDTH-1:0] ep_fifo                                    [0:VOX_FIFO_DEPTH-1] [0:MAX_VOXEL_NUM-1];
    reg  [              VN_WIDTH-1:0] ep_fifo_pnum                               [0:VOX_FIFO_DEPTH-1];
    reg  [           VOX_FIFO_AW-1:0] fifo_wr_ptr;
    reg  [           VOX_FIFO_AW-1:0] fifo_rd_ptr;
    reg  [             VOX_FIFO_AW:0] fifo_count;  // 0~4
    wire                              fifo_empty = (fifo_count == 0);
    wire                              fifo_full = (fifo_count == VOX_FIFO_DEPTH);

    // serializer 发完一个 voxel
    assign st4_push = st4_valid && !fifo_full;
    wire voxel_pop;
    wire [3:0] total_occupancy = inflight_cnt + (st3_valid ? 4'd1 : 4'd0) + (st4_valid ? 4'd1 : 4'd0) + fifo_count;
    assign pipe_stall = (total_occupancy >= (VOX_FIFO_DEPTH + 2));

    // always @(posedge clk) begin
    //     if (rst_n && st4_valid && fifo_full && !voxel_pop && st4_ready_for_new) begin
    //         $display("ERROR: Stage4 blocked by full FIFO without backpressure relief.");
    //         // $stop;
    //     end
    // end

    integer fi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= {VOX_FIFO_AW{1'b0}};
            fifo_rd_ptr <= {VOX_FIFO_AW{1'b0}};
            fifo_count  <= {(VOX_FIFO_AW + 1) {1'b0}};
        end else begin
            case ({
                st4_push, voxel_pop
            })
                2'b10: begin
                    // push only
                    ep_fifo_pnum[fifo_wr_ptr] <= st4_pnum;
                    for (fi = 0; fi < MAX_VOXEL_NUM; fi = fi + 1) begin
                        if (fi < st4_pnum) begin
                            ep_fifo[fifo_wr_ptr][fi] <= {
                                st4_points_buffer[fi][63-:16],
                                st4_points_buffer[fi][47-:16],
                                st4_points_buffer[fi][31-:16],
                                st4_points_buffer[fi][15-:16],
                                16'd0,
                                $signed(st4_points_buffer[fi][63-:16]) - st4_mean_x,
                                $signed(st4_points_buffer[fi][47-:16]) - st4_mean_y,
                                $signed(st4_points_buffer[fi][31-:16]) - st4_mean_z,
                                $signed(st4_points_buffer[fi][63-:16]) - st4_vx_fix16,
                                $signed(st4_points_buffer[fi][47-:16]) - st4_vy_fix16,
                                $signed(st4_points_buffer[fi][31-:16]) - st4_vz_fix16
                            };
                        end else begin
                            ep_fifo[fifo_wr_ptr][fi] <= {EXPAND_PT_DIM * PT_WIDTH{1'b0}};
                        end
                    end

                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                    fifo_count  <= fifo_count + 1'b1;
                end

                2'b01: begin
                    // pop only
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                    fifo_count  <= fifo_count - 1'b1;
                end

                2'b11: begin
                    // push + pop 同时发生，count 不变
                    ep_fifo_pnum[fifo_wr_ptr] <= st4_pnum;
                    for (fi = 0; fi < MAX_VOXEL_NUM; fi = fi + 1) begin
                        if (fi < st4_pnum) begin
                            ep_fifo[fifo_wr_ptr][fi] <= {
                                st4_points_buffer[fi][63-:16],
                                st4_points_buffer[fi][47-:16],
                                st4_points_buffer[fi][31-:16],
                                st4_points_buffer[fi][15-:16],
                                16'd0,
                                $signed(st4_points_buffer[fi][63-:16]) - st4_mean_x,
                                $signed(st4_points_buffer[fi][47-:16]) - st4_mean_y,
                                $signed(st4_points_buffer[fi][31-:16]) - st4_mean_z,
                                $signed(st4_points_buffer[fi][63-:16]) - st4_vx_fix16,
                                $signed(st4_points_buffer[fi][47-:16]) - st4_vy_fix16,
                                $signed(st4_points_buffer[fi][31-:16]) - st4_vz_fix16
                            };
                        end else begin
                            ep_fifo[fifo_wr_ptr][fi] <= {EXPAND_PT_DIM * PT_WIDTH{1'b0}};
                        end
                    end

                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                end

                default: begin
                    // hold
                end
            endcase
        end
    end

    // =========================================================================
    // Stage 6: 基于 4-entry FIFO 的序列化输出（look-ahead rd_ptr/count 无缝切换版）
    // =========================================================================
    reg [VN_WIDTH-1:0] point_cnt;
    reg serialize_busy;

    // 当前 FIFO 头信息
    wire [VN_WIDTH-1:0] cur_head_pnum = ep_fifo_pnum[fifo_rd_ptr];

    // 当前 busy 态下，这一拍是否正在发送当前 voxel 的最后一个点
    wire cur_last_fire = serialize_busy && (point_cnt == (cur_head_pnum - {{(VN_WIDTH - 1) {1'b0}}, 1'b1}));
    assign voxel_pop = cur_last_fire |
                   (!serialize_busy && !fifo_empty &&
                    (ep_fifo_pnum[fifo_rd_ptr] == {{(VN_WIDTH - 1){1'b0}},1'b1}));
    wire [VOX_FIFO_AW-1:0] rd_ptr_after = fifo_rd_ptr + 1'b1;

    wire [VOX_FIFO_AW:0] fifo_count_after =
        fifo_count
        + (st4_push ? {{VOX_FIFO_AW{1'b0}},1'b1} : {(VOX_FIFO_AW+1){1'b0}})
        - (cur_last_fire ? {{VOX_FIFO_AW{1'b0}},1'b1} : {(VOX_FIFO_AW+1){1'b0}});

    wire fifo_empty_after = (fifo_count_after == {(VOX_FIFO_AW + 1) {1'b0}});

    // “下一头部”的 pnum/data
    wire [VN_WIDTH-1:0] next_head_pnum = ep_fifo_pnum[rd_ptr_after];
    wire flag_writing_readnext = (fifo_wr_ptr == rd_ptr_after) ? 1'b1 : 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serialize_busy   <= 1'b0;
            point_cnt        <= {VN_WIDTH{1'b0}};
            m_axis_pfe_valid <= 1'b0;
            m_axis_pfe_data  <= {EXPAND_PT_DIM * PT_WIDTH{1'b0}};
            m_axis_pfe_last  <= 1'b0;
            // voxel_pop        <= 1'b0;
        end else begin
            // 默认
            m_axis_pfe_valid <= 1'b0;
            m_axis_pfe_last  <= 1'b0;
            // voxel_pop        <= 1'b0;

            if (serialize_busy) begin
                m_axis_pfe_valid <= 1'b1;
                m_axis_pfe_data  <= ep_fifo[fifo_rd_ptr][point_cnt];

                if (cur_last_fire) begin
                    m_axis_pfe_last <= 1'b1;
                    // voxel_pop       <= 1'b1;
                    if (!fifo_empty_after) begin
                        if (next_head_pnum == {{(VN_WIDTH - 1) {1'b0}}, 1'b1}) begin
                            serialize_busy <= 1'b0;
                            point_cnt      <= {VN_WIDTH{1'b0}};
                        end else begin
                            serialize_busy <= 1'b0;
                            point_cnt      <= {VN_WIDTH{1'b0}};
                        end
                    end else begin
                        serialize_busy <= 1'b0;
                        point_cnt      <= {VN_WIDTH{1'b0}};
                    end
                end else begin
                    // 当前 voxel 还没发完
                    point_cnt <= point_cnt + {{(VN_WIDTH - 1) {1'b0}}, 1'b1};
                end

            end else begin
                // -----------------------------
                // idle/start: 启动发送当前 FIFO 头
                // 注意：这里直接用“当前寄存器态”的 fifo_rd_ptr/fifo_empty
                // 因为上一个 voxel 若在上一拍最后一点结束，
                // 其 pop 已经在 FIFO always 块里更新完毕，这一拍 fifo_rd_ptr 已是新头
                // -----------------------------
                if (!fifo_empty) begin
                    m_axis_pfe_valid <= 1'b1;
                    m_axis_pfe_data  <= ep_fifo[fifo_rd_ptr][0];

                    if (ep_fifo_pnum[fifo_rd_ptr] == {{(VN_WIDTH - 1) {1'b0}}, 1'b1}) begin
                        // 单点 voxel：本拍直接发完
                        m_axis_pfe_last <= 1'b1;
                        // voxel_pop       <= 1'b1;
                        serialize_busy  <= 1'b0;
                        point_cnt       <= {VN_WIDTH{1'b0}};
                    end else begin
                        // 多点 voxel：本拍发 idx0，下一拍从 idx1 开始
                        serialize_busy <= 1'b1;
                        point_cnt      <= {{(VN_WIDTH - 1) {1'b0}}, 1'b1};
                    end
                end else begin
                    serialize_busy <= 1'b0;
                    point_cnt      <= {VN_WIDTH{1'b0}};
                end
            end
        end
    end


endmodule

