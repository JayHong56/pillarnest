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
    output reg                          S_AXIS_DRAM_TREADY,

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


    wire         s_fire = S_AXIS_DRAM_TVALID && S_AXIS_DRAM_TREADY;
    reg  [127:0] point_raw_r;
    reg          point_raw_vld;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            point_raw_r   <= 128'd0;
            point_raw_vld <= 1'b0;
        end else begin
            // 默认：这一拍没抓到新输入，就认为无效
            point_raw_vld <= 1'b0;
            if (s_fire) begin
                point_raw_r   <= S_AXIS_DRAM_TDATA;
                point_raw_vld <= 1'b1;
            end
        end
    end

    wire                                    prep_valid = point_raw_vld;
    wire        [                    127:0] point_raw = point_raw_r;

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

    // ------------------------------------------------------------
    // 1) voxel_x / voxel_y 计算（沿用你原逻辑）
    // ------------------------------------------------------------
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
    reg keep_point;
    always @(*) begin
        if (!rst_n) begin
            keep_point <= 1'b0;
            // end else if (point_raw == 128'd0) begin // invaild data 
            //     keep_point <= 1'b0;
        end else if ((ABS_pt_x_fix16 <= THRESHOLD_CLOSE) && (ABS_pt_y_fix16 <= THRESHOLD_CLOSE)) begin
            keep_point <= 1'b0;
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

    // 2) FIFO：缓冲预处理输出（voxel_x/y + point_proc）
    localparam integer FIFO_W = (2 * VOXEL_WIDTH + 64);
    localparam integer FIFO_DEPTH = 4;
    wire                            fifo_in_ready;
    wire                            fifo_out_valid;
    wire                            fifo_out_ready;
    wire [              FIFO_W-1:0] fifo_out_data;
    wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_level;
    wire [              FIFO_W-1:0] fifo_in_data = {voxel_x, voxel_y, point_proc_comb};
    // push：预处理有效 && keep && FIFO 有空间
    wire                            fifo_push = prep_valid && keep_point && fifo_in_ready;
    hash_expire_fifo_sync #(
        .WIDTH(FIFO_W),
        .DEPTH(FIFO_DEPTH)
    ) u_preprocess_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (fifo_push),
        .in_ready (fifo_in_ready),
        .in_data  (fifo_in_data),
        .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready),
        .out_data (fifo_out_data),
        .level    (fifo_level)
    );

    // AXIS 反压：保守策略，保证未来 PRE_LAT 拍后的 push 不会溢出 FIFO
    localparam integer PIPE_GUARD = (PRE_LAT + 2);  // 留冗余
    wire axis_can_accept = (fifo_level <= (FIFO_DEPTH - PIPE_GUARD));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) S_AXIS_DRAM_TREADY <= 1'b0;
        else S_AXIS_DRAM_TREADY <= axis_can_accept;
    end

    // FIFO -> hash：每拍 pop 一条发 req_valid（严格 1 拍脉冲）
    wire [VOXEL_WIDTH-1:0] fifo_key_x = fifo_out_data[FIFO_W-1-:VOXEL_WIDTH];
    wire [VOXEL_WIDTH-1:0] fifo_key_y = fifo_out_data[FIFO_W-VOXEL_WIDTH-1-:VOXEL_WIDTH];
    wire [           63:0] fifo_pproc = fifo_out_data[63:0];

    // 本设计默认 hash/后级每拍可吃 1 条（如需节流，把 hash_can_take 拉低即可）
    wire                   hash_can_take = 1'b1;
    wire                   fifo_pop = fifo_out_valid && hash_can_take;
    assign fifo_out_ready = hash_can_take;  // out_ready=1 时，只要 out_valid 就会 pop

    // hash req_valid = pop（单拍）
    wire hash_req_valid = fifo_pop;

    // ------------------------------------------------------------
    // 5) hash 表实例
    // ------------------------------------------------------------
    wire hash_found;
    wire hash_busy;
    wire hash_table_full;
    wire [HASH_ADDR_WIDTH-1:0] hash_out_idx;
    wire [VN_WIDTH-1:0] hash_out_point_number;
    hash_bucket_table #(
        .COORD_WIDTH      (VOXEL_WIDTH),
        .VN_WIDTH         (VN_WIDTH),
        .LIFE_CYCLE       (LIFE_CYCLE),
        .TIMER_WIDTH      (16),               // max 37560
        .ADDR_WIDTH       (HASH_ADDR_WIDTH),
        .BUCKETS          (64),
        .BUCKET_SLOT_WIDTH(2)
    ) u_hash_table_tombstone (
        .clk      (clk),
        .rst_n    (rst_n),
        .req_valid(hash_req_valid),
        .key_x    (fifo_key_x),
        .key_y    (fifo_key_y),

        .busy            (hash_busy),
        .found           (hash_found),
        .out_idx         (hash_out_idx),
        .out_point_number(hash_out_point_number),
        .table_full      (hash_table_full),

        .m_axis_expire_tready(m_axis_expire_tready),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tdata (m_axis_expire_tdata)
    );

    // ---------------------------voxel_brams写对齐 (delay = 3)-------------------------
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
            pproc_vld_d1 <= fifo_pop;
            pproc_vld_d2 <= pproc_vld_d1;
            pproc_vld_d3 <= pproc_vld_d2;

            if (fifo_pop) pproc_d1 <= fifo_pproc;
            pproc_d2 <= pproc_d1;
            pproc_d3 <= pproc_d2;
        end
    end

    assign bram_wrdata = {4{pproc_d3}};
    // ------------------------------------------------------------
    // 7) BRAM 地址/槽位计算（修正：加入 (point_number-1)>>2 与 slot 0-based）
    // ------------------------------------------------------------
    wire [BRAM_ADDR_WIDTH-1:0] bram_row_addr = (hash_out_idx * EXPEND_VOXEL_ROW) + (hash_out_point_number >> 2);  // +0..4
    wire [1:0] bram_slot_idx = hash_out_point_number[1:0];  // 0..3

    function [BRAM_DATA_WIDTH/8-1:0] slot_bwen_64;
        input [1:0] slot;
        begin
            case (slot)
                2'd0: slot_bwen_64 = 32'hFF000000;  // bytes [7:0]   -> bits [63:0]
                2'd1: slot_bwen_64 = 32'h000000FF;  // bytes [15:8]  -> bits [127:64]
                2'd2: slot_bwen_64 = 32'h0000FF00;  // bytes [23:16] -> bits [191:128]
                2'd3: slot_bwen_64 = 32'h00FF0000;  // bytes [31:24] -> bits [255:192]
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // 8) 响应拍写 BRAM：hash_busy=1 表示 out_* 有效
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
            // 只有当 resp_valid 且我们确实在上一拍 pop 过（对齐）才写
            if (resp_valid && pproc_vld_d3) begin
                // hash_found 表示 hit 或者新插入成功；table_full 时 found=0
                // 同时加一个上限：每体素最多 20 点
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
