module voxel_coor_pipe #(
    parameter integer        BRAM_DATA_WIDTH          = 640,       // 4 * 64
    parameter integer        BRAM_ADDR_WIDTH          = 9,         // 128pillar * 5brams
    parameter integer        AXIS_DATA_WIDTH          = 128,
    parameter integer        AXIS_ADDR_WIDTH          = 16,
    parameter integer        HASH_ADDR_WIDTH          = 8,         // log2(HASH_TABLE_SIZE)
    parameter         [15:0] THRESHOLD_CLOSE          = 16'h0100,  // 1.00m
    parameter         [15:0] THRESHOLD_BOUDARY        = 16'h3600,  // 54.00m
    parameter         [15:0] THRESHOLD_BOUDARY_Z_LOW  = 16'h0500,  // -5m
    parameter         [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h0300,  // +3m
    parameter integer        PRE_LAT                  = 0,         // 预处理固定延迟（拍数占位）
    parameter         [15:0] LIFE_CYCLE               = 16'd100
) (
    input wire clk,
    input wire rst_n,

    // AXI-Stream in (from DRAM FIFO)
    input  wire [  AXIS_DATA_WIDTH-1:0] s_axis_dram_data,
    input  wire [AXIS_DATA_WIDTH/8-1:0] s_axis_dram_keep,
    input  wire                         s_axis_dram_last,
    input  wire                         s_axis_dram_valid,
    output wire                         s_axis_dram_ready,
    // BRAM Native Interface
    output wire                         bram_voxelpoint_clk,
    output wire                         bram_voxelpoint_rst,
    output reg                          bram_voxelpoint_wr,
    output reg  [BRAM_DATA_WIDTH/8-1:0] bram_voxelpoint_bwen,   // 32-bit Byte Enable
    output reg  [  BRAM_ADDR_WIDTH-1:0] bram_voxelpoint_addr,   // 10-bit Address
    output reg  [  BRAM_DATA_WIDTH-1:0] bram_voxelpoint_wrdata, // 256-bit Data

    output wire                       bram_expire_clk_a,
    // output wire                         bram_expire_rst_a,
    // output wire                         bram_expire_wr_a,
    // output wire [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_a,   // 32-bit Byte Enable
    output wire [BRAM_ADDR_WIDTH-1:0] bram_expire_addr_a,  // 10-bit Address
    input  wire [BRAM_DATA_WIDTH-1:0] bram_expire_rdata_a, // 256-bit Data

    output wire                         bram_expire_clk_b,
    output wire                         bram_expire_rst_b,
    output wire                         bram_expire_wr_b,
    output wire [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_b,   // 32-bit Byte Enable
    output wire [  BRAM_ADDR_WIDTH-1:0] bram_expire_addr_b,   // 10-bit Address
    output wire [  BRAM_DATA_WIDTH-1:0] bram_expire_wrdata_b, // 256-bit Data

    // AXI-Stream out (expire voxel coordinates)
    output wire                            m_axis_expire_tvalid,
    input  wire                            m_axis_expire_tready,
    output wire [22+BRAM_ADDR_WIDTH+5-1:0] m_axis_expire_tdata
);

    localparam integer PT_WIDTH_I = 8;
    localparam integer PT_WIDTH_F = 8;
    localparam integer PT_WIDTH = PT_WIDTH_I + PT_WIDTH_F;  // 16
    localparam integer PT_WIDTH_FLOAT32 = 32;
    localparam integer VOXEL_WIDTH = 11;

    localparam [23:0] MAX_VOXEL_NUM = 24'd20;  // 每体素最多 20 点
    localparam integer VN_WIDTH = 5;  // 点编号宽度（hash 表输出 1..）
    localparam integer POINTS_PER_ROW = BRAM_DATA_WIDTH / (4 * PT_WIDTH);  // 640/64 = 10
    localparam integer EXPEND_VOXEL_ROW = (MAX_VOXEL_NUM + POINTS_PER_ROW - 1) / POINTS_PER_ROW;  // ceil(20/10)=2

    // BRAM clk/rst
    assign bram_voxelpoint_clk = clk;
    assign bram_voxelpoint_rst = ~rst_n;

    wire                          hash_req_ready;
    wire                          hash_req_valid;
    wire                          hash_fire = hash_req_valid && hash_req_ready;

    reg                           keep_point;
    reg  [PT_WIDTH_FLOAT32*4-1:0] point_raw_r;
    reg                           point_raw_vld;
    wire                          s_fire = s_axis_dram_valid && s_axis_dram_ready;
    // point_raw_val, keep_point, hash_fire
    // 1/0 : 当前点不在有效范围内
    // 0/? : 当前点无效，且没有新点进来，等待s_fire握手
    // 1/1/0 : 当前点有效，但 hash 表未准备好
    wire                          upstream_can_accept = (!point_raw_vld) || (!keep_point) || hash_fire;
    assign s_axis_dram_ready = upstream_can_accept;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            point_raw_r   <= {PT_WIDTH_FLOAT32 * 4{1'b0}};
            point_raw_vld <= 1'b0;
        end else begin
            if (s_fire) begin
                point_raw_r   <= s_axis_dram_data;
                point_raw_vld <= 1'b1;
            end else if (upstream_can_accept) begin
                // 没有新数据进来，但当前数据已经被处理（丢弃或发往下游），清空有效位
                point_raw_vld <= 1'b0;
            end
        end
    end

    wire        [   PT_WIDTH_FLOAT32*4-1:0] point_raw = point_raw_r;
    // unpack
    wire        [     PT_WIDTH_FLOAT32-1:0] pt_x_float32 = point_raw[127:96];
    wire        [     PT_WIDTH_FLOAT32-1:0] pt_y_float32 = point_raw[95:64];
    wire        [     PT_WIDTH_FLOAT32-1:0] pt_z_float32 = point_raw[63:32];
    wire        [     PT_WIDTH_FLOAT32-1:0] pt_intensity_float32 = point_raw[31:0];

    // float to fixed
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_x_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_y_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_z_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_intensity_fix16;
    float_to_fixed float2fxp_x (
        .float_in        (pt_x_float32),
        .true_fixed_value(pt_x_fix16),
        .fixed_sign      ()
    );
    float_to_fixed float2fxp_y (
        .float_in        (pt_y_float32),
        .true_fixed_value(pt_y_fix16),
        .fixed_sign      ()
    );
    float_to_fixed float2fxp_z (
        .float_in        (pt_z_float32),
        .true_fixed_value(pt_z_fix16),
        .fixed_sign      ()
    );
    float_to_fixed float2fxp_intensity (
        .float_in        (pt_intensity_float32),
        .true_fixed_value(pt_intensity_fix16),
        .fixed_sign      ()
    );

    // 1) voxel_x / voxel_y 计算（沿用你原逻辑）
    localparam signed [1+19-1:0] MULT_FACTOR = 20'd436907;  // 6.66666 缩放倍数
    reg signed [PT_WIDTH_I+PT_WIDTH_F-1:0] bourdary_fix16 = 16'h3600;  // 54(Q8.8)

    wire [PT_WIDTH_I+PT_WIDTH_F-1:0] fxp_add_x_out;
    wire [PT_WIDTH_I+PT_WIDTH_F+20-1:0] fxp_mul_x_out;

    fxp_add #(
        .WIIA (PT_WIDTH_I),
        .WIFA (PT_WIDTH_F),
        .WIIB (PT_WIDTH_I),
        .WIFB (PT_WIDTH_F),
        .WOI  (PT_WIDTH_I),
        .WOF  (PT_WIDTH_F),
        .ROUND(1)
    ) fxp_add_voxel_x (
        .ina     (pt_x_fix16),
        .inb     (bourdary_fix16),
        .out     (fxp_add_x_out),
        .overflow()
    );

    fxp_mul #(
        .WIIA (PT_WIDTH_I),
        .WIFA (PT_WIDTH_F),
        .WIIB (20),
        .WIFB (0),
        .WOI  (36),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_voxel_x (
        .ina     (fxp_add_x_out),
        .inb     (MULT_FACTOR),
        .out     (fxp_mul_x_out),
        .overflow()
    );

    wire [PT_WIDTH_I+PT_WIDTH_F-1:0] fxp_add_y_out;
    wire [PT_WIDTH_I+PT_WIDTH_F+20-1:0] fxp_mul_y_out;

    fxp_add #(
        .WIIA (PT_WIDTH_I),
        .WIFA (PT_WIDTH_F),
        .WIIB (PT_WIDTH_I),
        .WIFB (PT_WIDTH_F),
        .WOI  (PT_WIDTH_I),
        .WOF  (PT_WIDTH_F),
        .ROUND(1)
    ) fxp_add_voxel_y (
        .ina     (pt_y_fix16),
        .inb     (bourdary_fix16),
        .out     (fxp_add_y_out),
        .overflow()
    );

    fxp_mul #(
        .WIIA (PT_WIDTH_I),
        .WIFA (PT_WIDTH_F),
        .WIIB (20),
        .WIFB (0),
        .WOI  (36),
        .WOF  (0),
        .ROUND(1)
    ) fxp_mul_voxel_y (
        .ina     (fxp_add_y_out),
        .inb     (MULT_FACTOR),
        .out     (fxp_mul_y_out),
        .overflow()
    );

    // 截断成体素坐标
    wire [VOXEL_WIDTH-1:0] voxel_x = fxp_mul_x_out[16+VOXEL_WIDTH-1:16];
    wire [VOXEL_WIDTH-1:0] voxel_y = fxp_mul_y_out[16+VOXEL_WIDTH-1:16];

    // abs
    wire [15:0] ABS_pt_x_fix16 = (pt_x_fix16[15]) ? (~pt_x_fix16 + 1'b1) : pt_x_fix16;
    wire [15:0] ABS_pt_y_fix16 = (pt_y_fix16[15]) ? (~pt_y_fix16 + 1'b1) : pt_y_fix16;
    wire [15:0] ABS_pt_z_fix16 = (pt_z_fix16[15]) ? (~pt_z_fix16 + 1'b1) : pt_z_fix16;

    // keep_point（组合）
    always @(*) begin
        if (!rst_n) begin
            keep_point <= 1'b0;
            // end else if (point_raw == 128'd0) begin // invaild data 
            //     keep_point <= 1'b0;
            // end else if ((ABS_pt_x_fix16 <= THRESHOLD_CLOSE) && (ABS_pt_y_fix16 <= THRESHOLD_CLOSE)) begin
            //     keep_point <= 1'b0;
        end else if (ABS_pt_x_fix16 > THRESHOLD_BOUDARY || ABS_pt_y_fix16 > THRESHOLD_BOUDARY) begin
            keep_point <= 1'b0;
        end else if (ABS_pt_z_fix16[15] ? (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_LOW) :
                                          (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_HIGH)) begin
            keep_point <= 1'b0;
        end else begin
            keep_point <= 1'b1;
        end
    end

    // point_proc 组合值（Q8.8 拼起来）
    wire [63:0] point_proc_comb = {pt_x_fix16, pt_y_fix16, pt_z_fix16, pt_intensity_fix16};

    assign hash_req_valid = point_raw_vld && keep_point;

    // Hash 表的输入数据
    wire [    VOXEL_WIDTH-1:0] hash_key_x = voxel_x;
    wire [    VOXEL_WIDTH-1:0] hash_key_y = voxel_y;


    wire                       hash_found;
    wire                       hash_busy;
    wire                       hash_table_full;
    wire [HASH_ADDR_WIDTH-1:0] hash_out_idx;
    wire [       VN_WIDTH-1:0] hash_out_point_number;
    hash_bucket_table #(
        .COORD_WIDTH      (VOXEL_WIDTH),
        .VN_WIDTH         (VN_WIDTH),
        .LIFE_CYCLE       (LIFE_CYCLE),
        .TIMER_WIDTH      (16),               // NOTE max 37650
        .ADDR_WIDTH       (HASH_ADDR_WIDTH),
        .BUCKETS          (64),
        .BUCKET_SLOT_WIDTH(2),
        .BRAM_ADDR_WIDTH  (BRAM_ADDR_WIDTH),
        .BRAM_DATA_WIDTH  (BRAM_DATA_WIDTH)
    ) u_hash_table_tombstone (
        .clk                 (clk),
        .rst_n               (rst_n),
        .req_ready           (hash_req_ready),
        .req_valid           (hash_req_valid),
        .key_x               (hash_key_x),
        .key_y               (hash_key_y),
        .busy                (hash_busy),
        .found               (hash_found),
        .out_idx             (hash_out_idx),           // 0-255
        .out_point_number    (hash_out_point_number),  // 1-20
        .table_full          (hash_table_full),
        .bram_expire_clk_a   (bram_expire_clk_a),
        // .bram_expire_rst_a   (bram_expire_rst_a),
        // .bram_expire_wr_a    (bram_expire_wr_a),
        // .bram_expire_bwen_a  (bram_expire_bwen_a),     // 32-bit Byte Enable
        .bram_expire_addr_a  (bram_expire_addr_a),     // 10-bit Address
        .bram_expire_rdata_a (bram_expire_rdata_a),    // 256-bit Data
        .bram_expire_clk_b   (bram_expire_clk_b),
        .bram_expire_rst_b   (bram_expire_rst_b),
        .bram_expire_wr_b    (bram_expire_wr_b),
        .bram_expire_bwen_b  (bram_expire_bwen_b),     // 32-bit Byte Enable
        .bram_expire_addr_b  (bram_expire_addr_b),     // 10-bit Address
        .bram_expire_wrdata_b(bram_expire_wrdata_b),   // 256-bit Data
        .m_axis_expire_tready(m_axis_expire_tready),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tdata (m_axis_expire_tdata)
    );

    // ---------------------------与 hash 对齐-------------------------
    reg [63:0] pproc_d1, pproc_d2, pproc_d3;
    reg pproc_vld_d1, pproc_vld_d2, pproc_vld_d3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pproc_d1 <= 64'd0;
            pproc_d2 <= 64'd0;
            pproc_d3 <= 64'd0;
            pproc_vld_d1 <= 1'b0;
            pproc_vld_d2 <= 1'b0;
            pproc_vld_d3 <= 1'b0;
        end else if (hash_req_ready) begin
            pproc_vld_d1 <= hash_fire;
            pproc_vld_d2 <= pproc_vld_d1;
            pproc_vld_d3 <= pproc_vld_d2;

            if (hash_fire) pproc_d1 <= point_proc_comb;
            pproc_d2 <= pproc_d1;
            pproc_d3 <= pproc_d2;
        end
    end

    // ------------------------------------------------------------
    // 7) BRAM 地址/槽位计算（修正：加入 (point_number-1)>>2 与 slot 0-based）
    // ------------------------------------------------------------
    wire [BRAM_ADDR_WIDTH-1:0] bram_row_addr = (hash_out_idx * EXPEND_VOXEL_ROW) + ((hash_out_point_number > POINTS_PER_ROW) ? {{(BRAM_ADDR_WIDTH-1){1'b0}}, 1'b1} : {(BRAM_ADDR_WIDTH-1){1'b0}});
    wire [3:0] bram_slot_idx = (hash_out_point_number - {{(VN_WIDTH-1) {1'b0}}, 1'b1}) % POINTS_PER_ROW;  // 0..3

    function [BRAM_DATA_WIDTH/8-1:0] slot_bwen_64;
        input [3:0] slot;
        reg [BRAM_DATA_WIDTH/8-1:0] mask;
        begin
            mask = {BRAM_DATA_WIDTH / 8{1'b0}};
            mask[slot*8+:8] = 8'hFF;
            slot_bwen_64 = mask;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_voxelpoint_wr <= 1'b0;
            bram_voxelpoint_bwen <= {BRAM_DATA_WIDTH / 8{1'b0}};
            bram_voxelpoint_wrdata <= {POINTS_PER_ROW{1'b0}};
            bram_voxelpoint_addr <= {BRAM_ADDR_WIDTH{1'b0}};
        end else begin
            bram_voxelpoint_wr   <= 1'b0;
            bram_voxelpoint_bwen <= {BRAM_DATA_WIDTH / 8{1'b0}};
            // 只有当 hash_busy 且我们确实在上一拍 pop 过（对齐）才写
            if (hash_busy && pproc_vld_d3) begin
                // hash_found 表示 hit 或者新插入成功；table_full 时 found=0
                // 同时加一个上限：每体素最多 20 点
                if (hash_found  && (hash_out_point_number <= MAX_VOXEL_NUM[VN_WIDTH-1:0])
                                && (hash_out_point_number != {VN_WIDTH{1'b0}})) begin
                    bram_voxelpoint_wr <= 1'b1;
                    bram_voxelpoint_addr <= bram_row_addr;
                    bram_voxelpoint_wrdata <= {POINTS_PER_ROW{pproc_d3}};
                    bram_voxelpoint_bwen <= slot_bwen_64(bram_slot_idx);
                end
            end
        end
    end

`ifndef SYNTHESIS
    reg [31:0] stall_cnt;  // 32位计数器，足够统计很长时间
    // 阻塞条件：有有效请求 (point_raw_vld && keep_point) 但 Hash 表未 Ready
    wire is_stalled = (point_raw_vld && keep_point) && (!hash_req_ready);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_cnt <= 32'd0;
        end else begin
            if (is_stalled) begin
                stall_cnt <= stall_cnt + 1'b1;
            end
        end
    end

wire test_reg = (voxel_x == 36'd305 && voxel_y == 36'd359) ? 1'b1 : 1'b0;  // 用于调试特定坐标的点是否被处理



`endif

endmodule
