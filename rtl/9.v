module voxel_coor_pipe #(
    parameter integer BRAM_DATA_WIDTH = 256,  // 4 * 64
    parameter integer BRAM_ADDR_WIDTH = 10,   // 128pillar * 5brams

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
    input  wire [  AXIS_DATA_WIDTH-1:0] S_AXIS_DRAM_TDATA,
    input  wire [AXIS_DATA_WIDTH/8-1:0] S_AXIS_DRAM_TKEEP,
    input  wire                         S_AXIS_DRAM_TLAST,
    input  wire                         S_AXIS_DRAM_TVALID,
    output wire                         S_AXIS_DRAM_TREADY, // 改为 wire，由组合逻辑驱动

    // BRAM Native Interface
    output wire                         bram_clk,
    output wire                         bram_rst,
    output reg                          bram_wr,
    output reg  [BRAM_DATA_WIDTH/8-1:0] bram_bwen,   // 32-bit Byte Enable
    output reg  [  BRAM_ADDR_WIDTH-1:0] bram_addr,   // 10-bit Address
    output wire [  BRAM_DATA_WIDTH-1:0] bram_wrdata, // 256-bit Data

    // AXI-Stream out (expire voxel coordinates)
    output wire              m_axis_expire_tvalid,
    input  wire              m_axis_expire_tready,
    output wire [22+7+5-1:0] m_axis_expire_tdata
);

    localparam integer PT_WIDTH_I = 8;
    localparam integer PT_WIDTH_F = 8;
    localparam integer VOXEL_WIDTH = 11;

    localparam [23:0] MAX_VOXEL_NUM = 24'd20;  // 每体素最多 20 点
    localparam integer VN_WIDTH = 5;  // 点编号宽度（hash 表输出 1..）
    localparam integer EXPEND_VOXEL_ROW = (MAX_VOXEL_NUM >> 2);  // 20/4=5

    // BRAM clk/rst
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;

    // -------------------------------------------------------------------------
    // 1. 输入反压控制与数据缓存逻辑
    // -------------------------------------------------------------------------
    
    // 下游哈希表是否准备好接收（由 u_hash_table_tombstone 输出）
    wire hash_req_ready; 
    
    // keep_point 是组合逻辑，依赖于 point_raw_r
    reg keep_point; 
    
    // [反压核心逻辑]
    // 我们可以接收新数据的条件：
    // 1. 当前寄存器为空 (!point_raw_vld)
    // 2. 或者，当前寄存器有数据，且该数据已被处理：
    //    a. 数据被过滤掉了 (!keep_point) -> 直接丢弃，视为处理完成
    //    b. 数据有效且下游已接收 (hash_req_ready) -> 握手成功
    wire upstream_can_accept = !point_raw_vld || (!keep_point) || hash_req_ready;
    
    assign S_AXIS_DRAM_TREADY = upstream_can_accept;
    
    wire s_fire = S_AXIS_DRAM_TVALID && S_AXIS_DRAM_TREADY;

    reg  [127:0] point_raw_r;
    reg          point_raw_vld;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            point_raw_r   <= 128'd0;
            point_raw_vld <= 1'b0;
        end else begin
            if (s_fire) begin
                // 有新数据进来，加载新数据，标记有效
                point_raw_r   <= S_AXIS_DRAM_TDATA;
                point_raw_vld <= 1'b1;
            end else if (upstream_can_accept) begin
                // 没有新数据进来，但当前数据已经被处理（丢弃或发往下游），清空有效位
                point_raw_vld <= 1'b0;
            end
            // 否则：保持 point_raw_r 和 point_raw_vld 不变（Backpressure Hold）
        end
    end

    wire [127:0] point_raw = point_raw_r;

    // -------------------------------------------------------------------------
    // 2. 预处理逻辑 (Float -> Fixed -> Voxel Coor) - 保持不变
    // -------------------------------------------------------------------------
    // unpack
    wire        [                     31:0] pt_x_float32 = point_raw[127:96];
    wire        [                     31:0] pt_y_float32 = point_raw[95:64];
    wire        [                     31:0] pt_z_float32 = point_raw[63:32];
    wire        [                     31:0] pt_intensity_float32 = point_raw[31:0];

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

    // 1) voxel_x / voxel_y 计算
    localparam signed [1+19-1:0] MULT_FACTOR = 20'd436907; 
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] bourdary_fix16 = 16'h3600; 

    wire [PT_WIDTH_I+PT_WIDTH_F-1:0] fxp_add_x_out;
    wire [PT_WIDTH_I+PT_WIDTH_F+20-1:0] fxp_mul_x_out;

    fxp_add #(
        .WIIA (PT_WIDTH_I), .WIFA (PT_WIDTH_F),
        .WIIB (PT_WIDTH_I), .WIFB (PT_WIDTH_F),
        .WOI  (PT_WIDTH_I), .WOF  (PT_WIDTH_F),
        .ROUND(1)
    ) fxp_add_voxel_x (
        .ina(pt_x_fix16), .inb(bourdary_fix16),
        .out(fxp_add_x_out), .overflow()
    );

    fxp_mul #(
        .WIIA (PT_WIDTH_I), .WIFA (PT_WIDTH_F),
        .WIIB (20), .WIFB (0),
        .WOI  (36), .WOF  (0),
        .ROUND(1)
    ) fxp_mul_voxel_x (
        .ina(fxp_add_x_out), .inb(MULT_FACTOR),
        .out(fxp_mul_x_out), .overflow()
    );

    wire [PT_WIDTH_I+PT_WIDTH_F-1:0] fxp_add_y_out;
    wire [PT_WIDTH_I+PT_WIDTH_F+20-1:0] fxp_mul_y_out;

    fxp_add #(
        .WIIA (PT_WIDTH_I), .WIFA (PT_WIDTH_F),
        .WIIB (PT_WIDTH_I), .WIFB (PT_WIDTH_F),
        .WOI  (PT_WIDTH_I), .WOF  (PT_WIDTH_F),
        .ROUND(1)
    ) fxp_add_voxel_y (
        .ina(pt_y_fix16), .inb(bourdary_fix16),
        .out(fxp_add_y_out), .overflow()
    );

    fxp_mul #(
        .WIIA (PT_WIDTH_I), .WIFA (PT_WIDTH_F),
        .WIIB (20), .WIFB (0),
        .WOI  (36), .WOF  (0),
        .ROUND(1)
    ) fxp_mul_voxel_y (
        .ina(fxp_add_y_out), .inb(MULT_FACTOR),
        .out(fxp_mul_y_out), .overflow()
    );

    // 截断成体素坐标
    wire [VOXEL_WIDTH-1:0] voxel_x = fxp_mul_x_out[16+VOXEL_WIDTH-1:16];
    wire [VOXEL_WIDTH-1:0] voxel_y = fxp_mul_y_out[16+VOXEL_WIDTH-1:16];

    // abs
    wire [15:0] ABS_pt_x_fix16 = (pt_x_fix16[15]) ? (~pt_x_fix16 + 1'b1) : pt_x_fix16;
    wire [15:0] ABS_pt_y_fix16 = (pt_y_fix16[15]) ? (~pt_y_fix16 + 1'b1) : pt_y_fix16;
    wire [15:0] ABS_pt_z_fix16 = (pt_z_fix16[15]) ? (~pt_z_fix16 + 1'b1) : pt_z_fix16;

    // keep_point（组合逻辑）
    always @(*) begin
        if (!rst_n) begin
            keep_point = 1'b0;
        end else if ((ABS_pt_x_fix16 <= THRESHOLD_CLOSE) && (ABS_pt_y_fix16 <= THRESHOLD_CLOSE)) begin
            keep_point = 1'b0;
        end else if (ABS_pt_x_fix16 > THRESHOLD_BOUDARY || ABS_pt_y_fix16 > THRESHOLD_BOUDARY) begin
            keep_point = 1'b0;
        end else if (ABS_pt_z_fix16[15] ? (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_LOW) :
                                          (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_HIGH)) begin
            keep_point = 1'b0;
        end else begin
            keep_point = 1'b1;
        end
    end

    // point_proc 组合值
    wire [63:0] point_proc_comb = {pt_x_fix16, pt_y_fix16, pt_z_fix16, pt_intensity_fix16};

    // ------------------------------------------------------------
    // 3) 直连 Hash 表 (移除 FIFO)
    // ------------------------------------------------------------
    
    // 生成 Hash 请求信号
    // 只有当当前数据有效(point_raw_vld) 且 通过了过滤(keep_point) 时，才向 Hash 表发请求
    wire hash_req_valid = point_raw_vld && keep_point;
    
    // Hash 表的输入数据
    wire [VOXEL_WIDTH-1:0] hash_key_x = voxel_x;
    wire [VOXEL_WIDTH-1:0] hash_key_y = voxel_y;

    // Hash 表实例
    wire hash_found;
    wire hash_busy;
    wire hash_table_full;
    wire [HASH_ADDR_WIDTH-1:0] hash_out_idx;
    wire [VN_WIDTH-1:0] hash_out_point_number;

    hash_bucket_table #(
        .COORD_WIDTH      (VOXEL_WIDTH),
        .VN_WIDTH         (VN_WIDTH),
        .LIFE_CYCLE       (LIFE_CYCLE),
        .TIMER_WIDTH      (16),
        .ADDR_WIDTH       (HASH_ADDR_WIDTH),
        .BUCKETS          (64),
        .BUCKET_SLOT_WIDTH(2)
    ) u_hash_table_tombstone (
        .clk      (clk),
        .rst_n    (rst_n),
        
        // [新增] 反压信号
        .req_ready(hash_req_ready),     // Hash 表输出：我能接收请求吗？
        .req_valid(hash_req_valid),     // Pipe 输出：我有请求给你
        
        .key_x    (hash_key_x),
        .key_y    (hash_key_y),

        .busy            (hash_busy),
        .found           (hash_found),
        .out_idx         (hash_out_idx),
        .out_point_number(hash_out_point_number),
        .table_full      (hash_table_full),

        .m_axis_expire_tready(m_axis_expire_tready),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tdata (m_axis_expire_tdata)
    );

    // ------------------------------------------------------------
    // 4) Voxel BRAM 写对齐 (使用 Hash 握手成功信号驱动)
    // ------------------------------------------------------------
    
    // 只有当这次请求真正发给了 Hash 表（握手成功），我们才移动 Delay Line
    wire hash_fire = hash_req_valid && hash_req_ready;

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
        end else begin
            // 数据流水线随 hash_fire 移动
            pproc_vld_d1 <= hash_fire;
            pproc_vld_d2 <= pproc_vld_d1;
            pproc_vld_d3 <= pproc_vld_d2;

            if (hash_fire) pproc_d1 <= point_proc_comb;
            pproc_d2 <= pproc_d1;
            pproc_d3 <= pproc_d2;
        end
    end

    assign bram_wrdata = {4{pproc_d3}};

    // ------------------------------------------------------------
    // 5) BRAM 地址/槽位计算
    // ------------------------------------------------------------
    wire [BRAM_ADDR_WIDTH-1:0] bram_row_addr = (hash_out_idx * EXPEND_VOXEL_ROW) + (hash_out_point_number >> 2);
    wire [1:0] bram_slot_idx = hash_out_point_number[1:0];

    function [BRAM_DATA_WIDTH/8-1:0] slot_bwen_64;
        input [1:0] slot;
        begin
            case (slot)
                2'd0: slot_bwen_64 = 32'hFF000000;
                2'd1: slot_bwen_64 = 32'h000000FF;
                2'd2: slot_bwen_64 = 32'h0000FF00;
                2'd3: slot_bwen_64 = 32'h00FF0000;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // 6) 响应拍写 BRAM
    // ------------------------------------------------------------
    wire resp_valid = hash_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_wr   <= 1'b0;
            bram_bwen <= {BRAM_DATA_WIDTH / 8{1'b0}};
            bram_addr <= {BRAM_ADDR_WIDTH{1'b0}};
        end else begin
            bram_wr   <= 1'b0;
            bram_bwen <= {BRAM_DATA_WIDTH / 8{1'b0}};
            
            // 只有当 resp_valid 且数据流水线对齐有效时才写
            if (resp_valid && pproc_vld_d3) begin
                if (hash_found  && (hash_out_point_number <= MAX_VOXEL_NUM[VN_WIDTH-1:0])
                                && (hash_out_point_number != {VN_WIDTH{1'b0}})) begin
                    bram_wr   <= 1'b1;
                    bram_addr <= bram_row_addr;
                    bram_bwen <= slot_bwen_64(bram_slot_idx);
                end
            end
        end
    end

endmodule