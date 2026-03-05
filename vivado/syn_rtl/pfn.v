module pfn #(
    parameter COORD_WIDTH = 11,
    parameter PT_WIDTH = 16,
    parameter HASH_ADDR_WIDTH = 7,
    parameter MAX_VOXEL_NUM = 12'd20,
    parameter VN_WIDTH = 5,

    parameter ENPAND_PT_DIM = 11,  // x,y,z,intensity,0,(x-mean,y-mean,z-mean,intensity-mean),(x-vmean,y-vmean,z-vmean,intensity-vmean)
    parameter BRAM_DATA_WIDTH = 256,  // 64bit * 4
    parameter BRAM_ADDR_WIDTH = 10  // 128pillar * 5brams
) (

    input wire clk,
    input wire rst_n,

    input  wire                                       s_axis_expire_tvalid,
    output reg                                        s_axis_expire_tready,
    input  wire [2*COORD_WIDTH+HASH_ADDR_WIDTH+5-1:0] s_axis_expire_tdata,   // NOTE

    output wire                       bram_clk,
    output wire                       bram_rst,
    output reg  [BRAM_ADDR_WIDTH-1:0] bram_addr,  // 假设地址空间足够大
    output reg                        bram_en,
    input  wire [BRAM_DATA_WIDTH-1:0] bram_rdata,  // 255:0 ((9+7)*4 )*4points
    output reg [ENPAND_PT_DIM-1:0] debug_temp
);
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;
    // 注意：Verilog 切片最好用固定数值，或者确保 parameter 计算正确
    wire signed [COORD_WIDTH-1:0] axis_voxel_x    = s_axis_expire_tdata[2*COORD_WIDTH+HASH_ADDR_WIDTH+VN_WIDTH-1 -: COORD_WIDTH];
    wire signed [COORD_WIDTH-1:0] axis_voxel_y    = s_axis_expire_tdata[COORD_WIDTH+HASH_ADDR_WIDTH+VN_WIDTH-1     -: COORD_WIDTH];
    wire [HASH_ADDR_WIDTH-1:0] axis_bram_index = s_axis_expire_tdata[HASH_ADDR_WIDTH+VN_WIDTH-1-:HASH_ADDR_WIDTH];
    wire [VN_WIDTH-1:0] axis_point_num_indicator = s_axis_expire_tdata[VN_WIDTH-1 : 0];  // 1-20 points

    // -----------------------------------------------------------
    // 2. 内部存储 (Points Buffer) & 累加器
    // -----------------------------------------------------------
    // 存储该 Voxel 内的所有点，供后续处理 (Process 阶段) 使用
    localparam EXPAND_VOXEL_ROW = MAX_VOXEL_NUM >> 2;  // 20 / 4 = 5
    localparam integer PT_WIDTH_I = 7;
    localparam integer PT_WIDTH_F = 9;
    reg [4*PT_WIDTH-1:0] points_buffer[0:MAX_VOXEL_NUM-1];

    // 11 dimensions x 20 points
    reg [ENPAND_PT_DIM*PT_WIDTH-1:0] expanded_points_buffer[0:MAX_VOXEL_NUM-1];


    // 累加器 [(9+5) + 7] = Q14.7
    // [16 + 5 - 1:0]
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_x;
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_y;
    reg signed [PT_WIDTH+VN_WIDTH-1:0] sum_z;

    // 平均值结果
    reg signed [PT_WIDTH-1:0] mean_x;
    reg signed [PT_WIDTH-1:0] mean_y;
    reg signed [PT_WIDTH-1:0] mean_z;

    // 计数器
    reg [2:0] cnt_req;  // 0-4
    reg [2:0] cnt_recv;
    reg [VN_WIDTH-1:0] cnt_point;

    // 锁存 Point Num 防止握手后变化
    reg [VN_WIDTH-1:0] r_point_num_indicator;  // 1~20
    reg [HASH_ADDR_WIDTH-1:0] r_bram_index;
    reg [1:0] r_rd_vld_pipe;
    wire [1:0] last_row_points;  // 0-3
    wire [2:0] need_read_rows;  // 1-5
    assign need_read_rows  = ((r_point_num_indicator + 2'd3) >> 2);
    assign last_row_points = r_point_num_indicator[1:0];

    // ------------------------计算cluster center----------------------
    reg signed [1+17-1:0] reciprocal_coeff;  // 1.0 * 65536
    always @(*) begin
        case (r_point_num_indicator)
            5'd1: reciprocal_coeff = 18'd65536;  // 1/1
            5'd2: reciprocal_coeff = 18'd32768;  // 1/2
            5'd3: reciprocal_coeff = 18'd21845;  // 1/3
            5'd4: reciprocal_coeff = 18'd16384;  // 1/4
            5'd5: reciprocal_coeff = 18'd13107;  // 1/5
            5'd6: reciprocal_coeff = 18'd10923;  // 1/6
            5'd7: reciprocal_coeff = 18'd9362;  // 1/7
            5'd8: reciprocal_coeff = 18'd8192;  // 1/8
            5'd9: reciprocal_coeff = 18'd7282;  // 1/9
            5'd10: reciprocal_coeff = 18'd6554;  // 1/10
            5'd11: reciprocal_coeff = 18'd5958;  // 1/11
            5'd12: reciprocal_coeff = 18'd5461;  // 1/12
            5'd13: reciprocal_coeff = 18'd5041;  // 1/13
            5'd14: reciprocal_coeff = 18'd4681;  // 1/14
            5'd15: reciprocal_coeff = 18'd4369;  // 1/15
            5'd16: reciprocal_coeff = 18'd4096;  // 1/16
            5'd17: reciprocal_coeff = 18'd3855;  // 1/17
            5'd18: reciprocal_coeff = 18'd3641;  // 1/18
            5'd19: reciprocal_coeff = 18'd3449;  // 1/19
            5'd20: reciprocal_coeff = 18'd3277;  // 1/20
            default: reciprocal_coeff = 18'd0;
        endcase
    end

    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_x;
    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_y;
    wire signed [(PT_WIDTH+VN_WIDTH)+(17+1) -1:0] temp_mult_z;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_mult_voxel_x;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_mult_voxel_y;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_sub_voxel_x;
    wire signed [COORD_WIDTH+(17+1) -1:0] temp_sub_voxel_y;

    fxp_mul #(
        .WIIA (PT_WIDTH_I+VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_temp_mult_x (
        .ina(sum_x),
        .inb(reciprocal_coeff),
        .out(temp_mult_x),
        .overflow()
    );
    fxp_mul #(
        .WIIA (PT_WIDTH_I+VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_temp_mult_y (
        .ina(sum_y),
        .inb(reciprocal_coeff),
        .out(temp_mult_y),
        .overflow()
    );
    fxp_mul #(
        .WIIA (PT_WIDTH_I+VN_WIDTH),
        .WIFA (PT_WIDTH_F),
        .WIIB (18),
        .WIFB (0),
        .WOI  (39),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_temp_mult_z (
        .ina(sum_z),
        .inb(reciprocal_coeff),
        .out(temp_mult_z),
        .overflow()
    );


    // --------------------扩展voxel_center点坐标维度---------------------
    // voxel_x_fix16 = voxel_x * 0.15 - 54.0 + 0.075
    localparam signed [18-1:0] COEFF_SLOPE = 18'sd9830;  // 0.15
    localparam signed [23-1:0] COEFF_OFFSET = 23'sd3538944;  // 54.0
    reg signed [PT_WIDTH-1:0] voxel_x_fix16;
    reg signed [PT_WIDTH-1:0] voxel_y_fix16;
    reg signed [PT_WIDTH-1:0] voxel_z_fix16;

    fxp_mul #(
        .WIIA (COORD_WIDTH),
        .WIFA (0),
        .WIIB (18),
        .WIFB (0),
        .WOI  (29),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_temp_mult_voxel_x (
        .ina(axis_voxel_x),
        .inb(COEFF_SLOPE),
        .out(temp_mult_voxel_x),
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
    ) fxp_mul_temp_mult_voxel_y (
        .ina(axis_voxel_y),
        .inb(COEFF_SLOPE),
        .out(temp_mult_voxel_y),
        .overflow()
    );

    assign temp_sub_voxel_x = temp_mult_voxel_x - COEFF_OFFSET;
    assign temp_sub_voxel_y = temp_mult_voxel_y - COEFF_OFFSET;


    reg signed [PT_WIDTH-1:0] max_features [0:ENPAND_PT_DIM-1];

    // 为了在 S_EXPAND_DIM 状态下并行计算最大值，我们定义一组 wire
    // 注意：20 个数的比较逻辑层级较深，如果时序紧张需要加流水线
    integer k, d;
    reg signed [PT_WIDTH-1:0] current_val;
    reg signed [PT_WIDTH-1:0] temp_max [0:ENPAND_PT_DIM-1];

    always @(*) begin
        if (!rst_n) begin
            
        end else begin
            for (d = 0; d < ENPAND_PT_DIM; d = d + 1) begin
                debug_temp[d] = (max_features[d] == 16'h8000) ? 1'b0 : 1'b1;
            end
        end
    end


    // 组合逻辑：从 expanded_points_buffer 中找最大值
    // 只有在扩维数据准备好后 (pre_cnt >= 1) 这个逻辑才有效
    always @(*) begin
        // 初始化 temp_max 为极小值 (例如 16'h8000)
        for (d = 0; d < ENPAND_PT_DIM; d = d + 1) begin
            temp_max[d] = 16'h8000; // Negative Max
        end

        // 遍历所有有效点
        // 注意：这里只遍历 r_point_num_indicator 个点，不是 MAX_VOXEL_NUM
        for (k = 0; k < MAX_VOXEL_NUM; k = k + 1) begin
            if (k < r_point_num_indicator) begin
                for (d = 0; d < ENPAND_PT_DIM; d = d + 1) begin
                    // 从 buffer 中提取第 k 个点的第 d 个维度
                    // expanded_points_buffer[k] 是一个宽向量
                    // 格式: {dim0, dim1, ... dim10}
                    current_val = expanded_points_buffer[k][(ENPAND_PT_DIM-1-d)*PT_WIDTH +: PT_WIDTH];
                    
                    if (current_val > temp_max[d]) begin
                        temp_max[d] = current_val;
                    end
                end
            end
        end
    end


    // ------------------------------状态机-------------------------------
    localparam S_IDLE = 3'd0;
    localparam S_FETCH_PTS = 3'd1;
    localparam S_CALC_MEAN = 3'd2;
    localparam S_EXPAND_DIM = 3'd3;
    reg [2:0] state;
    wire s_fire = s_axis_expire_tvalid && s_axis_expire_tready;

    localparam PRE_LAT = 2;
    reg [$clog2(PRE_LAT+1)-1:0] pre_cnt;  // 扩维阶段计数器
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            s_axis_expire_tready <= 1'b0;
            bram_en <= 0;
            bram_addr <= 0;
            cnt_req <= 0;
            cnt_recv <= 0;
            cnt_point <= 0;

            sum_x <= 0;
            sum_y <= 0;
            sum_z <= 0;

            r_point_num_indicator <= 0;
            r_bram_index <= 0;
            pre_cnt <= 'd0;
            r_rd_vld_pipe <= 2'b0;  // 复位流水线
        end else begin
            case (state)
                S_IDLE: begin
                    s_axis_expire_tready <= 1'b1;
                    cnt_req <= 0;
                    cnt_recv <= 0;
                    cnt_point <= 0;

                    sum_x <= 0;
                    sum_y <= 0;
                    sum_z <= 0;

                    pre_cnt <= 'd0;
                    r_rd_vld_pipe <= 2'b0;  // 清空流水线

                    if (s_fire) begin
                        s_axis_expire_tready <= 1'b0;
                        // 锁存关键参数
                        r_point_num_indicator <= axis_point_num_indicator;
                        r_bram_index <= axis_bram_index;

                        if (axis_point_num_indicator > 0) begin
                            state   <= S_FETCH_PTS;
                            // 预读第一个点 (Pipeline Prime)
                            bram_en <= 1'b1;
                        end else begin
                            // 异常：空 Voxel
                            state <= S_IDLE;
                            s_axis_expire_tready <= 1'b1;
                        end
                    end
                end
 
                S_FETCH_PTS: begin  // 2 cycles BRAM read latency
                    if (cnt_req < need_read_rows) begin
                        bram_addr <= {r_bram_index * EXPAND_VOXEL_ROW} + cnt_req;  // 一个voxel最多有5行
                        cnt_req <= cnt_req + 1;
                        r_rd_vld_pipe[0] <= 1'b1;  // 表示 "这一拍我发起了有效请求"

                        state <= S_FETCH_PTS;
                    end else begin
                        // bram_en <= 1'b0;  // 请求发完了// NOTE 这里不要关掉，否则会漏掉最后的数据
                        r_rd_vld_pipe[0] <= 1'b0;  // 没有新请求了
                    end

                    r_rd_vld_pipe[1] <= r_rd_vld_pipe[0];


                    if (r_rd_vld_pipe[1] && cnt_recv < need_read_rows-1) begin // 读存满点的行
                        points_buffer[cnt_point] <= bram_rdata[63:0];
                        points_buffer[cnt_point+1] <= bram_rdata[127:64];
                        points_buffer[cnt_point+2] <= bram_rdata[191:128];
                        points_buffer[cnt_point+3] <= bram_rdata[255:192];
                        cnt_point <= cnt_point + 4;

                        sum_x <= sum_x + bram_rdata[255 -: 16] + bram_rdata[191 -: 16] + bram_rdata[127 -: 16] + bram_rdata[63 -: 16];
                        sum_y <= sum_y + bram_rdata[239 -: 16] + bram_rdata[175 -: 16] + bram_rdata[111 -: 16] + bram_rdata[47 -: 16];
                        sum_z <= sum_z + bram_rdata[223 -: 16] + bram_rdata[159 -: 16] + bram_rdata[95 -: 16] + bram_rdata[31 -: 16];

                        cnt_recv <= cnt_recv + 1;
                        state <= S_FETCH_PTS;
                    end else if (r_rd_vld_pipe[1] && cnt_recv == need_read_rows-1) begin // 最后一行
                        case (last_row_points)
                            2'd1: begin
                                points_buffer[cnt_point] <= bram_rdata[63:0];
                                sum_x <= sum_x + bram_rdata[63-:16];
                                sum_y <= sum_y + bram_rdata[47-:16];
                                sum_z <= sum_z + bram_rdata[31-:16];
                            end
                            2'd2: begin
                                points_buffer[cnt_point] <= bram_rdata[63:0];
                                points_buffer[cnt_point+1] <= bram_rdata[127:64];
                                sum_x <= sum_x + bram_rdata[127-:16] + bram_rdata[63-:16];
                                sum_y <= sum_y + bram_rdata[111-:16] + bram_rdata[47-:16];
                                sum_z <= sum_z + bram_rdata[95-:16] + bram_rdata[31-:16];
                            end
                            2'd3: begin
                                points_buffer[cnt_point] <= bram_rdata[63:0];
                                points_buffer[cnt_point+1] <= bram_rdata[127:64];
                                points_buffer[cnt_point+2] <= bram_rdata[191:128];
                                sum_x <= sum_x + bram_rdata[191 -: 16] + bram_rdata[127 -: 16] + bram_rdata[63 -: 16];
                                sum_y <= sum_y + bram_rdata[175 -: 16] + bram_rdata[111 -: 16] + bram_rdata[47 -: 16];
                                sum_z <= sum_z + bram_rdata[159 -: 16] + bram_rdata[95 -: 16] + bram_rdata[31 -: 16];
                            end
                            2'd0: begin
                                points_buffer[cnt_point] <= bram_rdata[63:0];
                                points_buffer[cnt_point+1] <= bram_rdata[127:64];
                                points_buffer[cnt_point+2] <= bram_rdata[191:128];
                                points_buffer[cnt_point+3] <= bram_rdata[255:192];
                                sum_x <= sum_x + bram_rdata[191 -: 16] + bram_rdata[127 -: 16] + bram_rdata[63 -: 16];
                                sum_y <= sum_y + bram_rdata[175 -: 16] + bram_rdata[111 -: 16] + bram_rdata[47 -: 16];
                                sum_z <= sum_z + bram_rdata[159 -: 16] + bram_rdata[95 -: 16] + bram_rdata[31 -: 16];
                            end

                            default: begin
                                sum_x <= sum_x;
                                sum_y <= sum_y;
                                sum_z <= sum_z;
                            end
                        endcase

                        cnt_point <= 0;
                        cnt_recv <= cnt_recv + 1;
                        state <= S_FETCH_PTS;
                    end else if (cnt_recv == need_read_rows) begin
                        state <= S_CALC_MEAN;
                        bram_en <= 1'b0;  // 读完了
                    end else begin
                        state <= S_FETCH_PTS;
                    end
                end

                S_CALC_MEAN: begin
                    // 利用 DSP 做乘法计算平均值
                    // Sum * (1/N) >> 16
                    // 注意：sum 是带符号的，reciprocal 是无符号的
                    mean_x <= temp_mult_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                    mean_y <= temp_mult_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                    mean_z <= temp_mult_z[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                    voxel_x_fix16 <= temp_sub_voxel_x[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                    voxel_y_fix16 <= temp_sub_voxel_y[16-PT_WIDTH_F+15:16-PT_WIDTH_F];
                    voxel_z_fix16 <= 16'hfe00;  // -1.0 Q7.9
                    state  <= S_EXPAND_DIM;
                end

                S_EXPAND_DIM: begin
                    if (pre_cnt == 'd0) begin
                        // 1. 执行扩维计算 (保持你原有的逻辑)
                        for (i = 0; i < MAX_VOXEL_NUM; i = i + 1) begin
                            expanded_points_buffer[i] <= {
                                points_buffer[i][63-:16],  // dim 0: x
                                points_buffer[i][47-:16],  // dim 1: y
                                points_buffer[i][31-:16],  // dim 2: z
                                points_buffer[i][15-:16],  // dim 3: intensity
                                16'd0,                     // dim 4: timestamp (0)
                                points_buffer[i][63-:16] - mean_x, // dim 5
                                points_buffer[i][47-:16] - mean_y, // dim 6
                                points_buffer[i][31-:16] - mean_z, // dim 7
                                points_buffer[i][63-:16] - voxel_x_fix16, // dim 8
                                points_buffer[i][47-:16] - voxel_y_fix16, // dim 9
                                points_buffer[i][31-:16] - voxel_z_fix16  // dim 10
                            };
                        end
                        pre_cnt <= pre_cnt + 1'b1;
                    end 
                    else if (pre_cnt == 'd1) begin
                        // 2. [新增] 锁存计算出的最大值
                        // 此时 expanded_points_buffer 已经稳定，组合逻辑 temp_max 已计算出结果
                        for (d = 0; d < ENPAND_PT_DIM; d = d + 1) begin
                            max_features[d] <= temp_max[d];
                        end
                        
                        pre_cnt <= pre_cnt + 1'b1;
                    end
                    else if (pre_cnt == PRE_LAT) begin // 修改 PRE_LAT 适应你的时序
                        pre_cnt <= 'd0;
                        state <= S_IDLE;
                        s_axis_expire_tready <= 1'b1; 
                        
                        // [可选] 这里可以将 max_features 输出到下一级模块
                        // o_max_features_valid <= 1'b1;
                        // o_max_features_data <= ...
                    end else begin
                        pre_cnt <= pre_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
        
endmodule

