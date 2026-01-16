module voxel_coor #(
    // ------------------------------------------------------------
    // 1. 参数修改：删除 AXI_LITE，添加 BRAM 参数
    // ------------------------------------------------------------
    parameter integer BRAM_DATA_WIDTH = 256,  // 4 * 64
    parameter integer BRAM_ADDR_WIDTH = 10,   // 128pillar * 5brams

    parameter integer AXIS_DATA_WIDTH = 128,
    parameter integer AXIS_ADDR_WIDTH = 16,
    parameter [15:0] THRESHOLD_CLOSE = 16'h0100,  // 1.00m
    parameter [15:0] THRESHOLD_BOUDARY = 16'h3600,  // 54.00m
    parameter [15:0] THRESHOLD_BOUDARY_Z_LOW = 16'h0500,  // -5m
    parameter [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h0300,  // +3m
    parameter integer PRE_LAT = 1  // 预处理固定延迟（拍数占位）
) (
    input wire clk,
    input wire rst_n,

    // AXI-Stream in (from DRAM FIFO)
    input  wire [  AXIS_DATA_WIDTH-1:0] S_AXIS_DRAM_TDATA,
    input  wire [AXIS_DATA_WIDTH/8-1:0] S_AXIS_DRAM_TKEEP,
    input  wire                         S_AXIS_DRAM_TLAST,
    input  wire                         S_AXIS_DRAM_TVALID,
    output reg                          S_AXIS_DRAM_TREADY,

    // ------------------------------------------------------------
    // 2. 接口替换：BRAM Native Interface
    // ------------------------------------------------------------
    // 注意：BRAM 侧通常需要 clk/rst，这里直接透传或在顶层连接
    output wire                         bram_clk,
    output wire                         bram_rst,
    output reg                          bram_wr,
    output reg  [BRAM_DATA_WIDTH/8-1:0] bram_bwen,   // 32-bit Byte Enable
    output reg  [  BRAM_ADDR_WIDTH-1:0] bram_addr,   // 10-bit Address
    output wire [  BRAM_DATA_WIDTH-1:0] bram_wrdata, // 256-bit Data

    // AXI-Stream out (expire voxel coordinates
    output wire              m_axis_expire_tvalid,
    input  wire              m_axis_expire_tready,
    output wire [22+7+5-1:0] m_axis_expire_tdata

);
    // ------------------------------------------------------------
    // 1) One-point buffer (capture one input beat)
    // ------------------------------------------------------------
    localparam integer PT_WIDTH_I = 8;
    localparam integer PT_WIDTH_F = 8;
    localparam VOXEL_WIDTH = 11;  // wire [10:0] voxel_x

    reg [127:0] point_raw;
    // 存到bram中的点数据
    reg [63:0] point_proc;
    // unpack (optional)
    wire [   31:0] pt_x_float32 = point_raw[127:96];
    wire [   31:0] pt_y_float32 = point_raw[95:64];
    wire [   31:0] pt_z_float32 = point_raw[63:32];
    wire [   31:0] pt_intensity_float32 = point_raw[31:0];

    // float to fixed point
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_x_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_y_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_z_fix16;
    wire signed [PT_WIDTH_I+PT_WIDTH_F-1:0] pt_intensity_fix16;
    float_to_fixed float2fxp_x (
        .float_in(pt_x_float32),
        .true_fixed_value(pt_x_fix16),
        .fixed_sign()
    );
    float_to_fixed float2fxp_y (
        .float_in(pt_y_float32),
        .true_fixed_value(pt_y_fix16),
        .fixed_sign()
    );
    float_to_fixed float2fxp_z (
        .float_in(pt_z_float32),
        .true_fixed_value(pt_z_fix16),
        .fixed_sign()
    );
    float_to_fixed float2fxp_intensity (
        .float_in(pt_intensity_float32),
        .true_fixed_value(pt_intensity_fix16),
        .fixed_sign()
    );

    // 转为体素坐标
    //  y = (x-(-54))/0.15 = 
    localparam signed [1+19-1:0] MULT_FACTOR = 20'd436907;  // 6.66666 缩放倍数
    reg signed [PT_WIDTH_I+PT_WIDTH_F-1:0] bourdary_fix16 = 16'h3600;  // 54 的固定点Q8.8表示
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
        .ina(pt_x_fix16),
        .inb(bourdary_fix16),
        .out(fxp_add_x_out),
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
        .ina(fxp_add_x_out),
        .inb(MULT_FACTOR),
        .out(fxp_mul_x_out),
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
        .ina(pt_y_fix16),
        .inb(bourdary_fix16),
        .out(fxp_add_y_out),
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
        .ina(fxp_add_y_out),
        .inb(MULT_FACTOR),
        .out(fxp_mul_y_out),
        .overflow()
    );

    // 截断
    wire [VOXEL_WIDTH-1:0] voxel_x = fxp_mul_x_out[16+VOXEL_WIDTH-1:16];
    wire [VOXEL_WIDTH-1:0] voxel_y = fxp_mul_y_out[16+VOXEL_WIDTH-1:16];
    // 取绝对值
    wire [15:0] ABS_pt_x_fix16;
    wire [15:0] ABS_pt_y_fix16;
    wire [15:0] ABS_pt_z_fix16;
    assign ABS_pt_x_fix16 = (pt_x_fix16[15]) ? (~pt_x_fix16 + 1'b1) : pt_x_fix16;
    assign ABS_pt_y_fix16 = (pt_y_fix16[15]) ? (~pt_y_fix16 + 1'b1) : pt_y_fix16;
    assign ABS_pt_z_fix16 = (pt_z_fix16[15]) ? (~pt_z_fix16 + 1'b1) : pt_z_fix16;


    reg keep_point;
    // boundary control
    always @(*) begin
        if (!rst_n) begin
            keep_point <= 1'b0;
            // end else if (point_raw == 128'd0) begin // invaild data 
            //     keep_point <= 1'b0;
        end else if ((ABS_pt_x_fix16 <= THRESHOLD_CLOSE) && (ABS_pt_y_fix16 <= THRESHOLD_CLOSE)) begin // too close
            keep_point <= 1'b0;
        end else if (ABS_pt_x_fix16 > THRESHOLD_BOUDARY || ABS_pt_y_fix16 > THRESHOLD_BOUDARY) begin // over boundary
            keep_point <= 1'b0;
        end else if (ABS_pt_z_fix16[15] ? (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_LOW) : 
                                            (ABS_pt_z_fix16 > THRESHOLD_BOUDARY_Z_HIGH)) begin // over z boundary
            keep_point <= 1'b0;
        end else begin
            keep_point <= 1'b1;
        end
    end


    // 体素存BRAM的索引哈希表
    reg hash_req_valid;
    reg hash_req_op;  // 0: read, 1: write
    localparam HASH_TABLE_SIZE = 128;
    localparam HASH_ADDR_WIDTH = 7;  // log2(HASH_TABLE_SIZE)=7
    localparam [23:0] MAX_VOXEL_NUM = 24'd20;  // 32-LSB(3)-5 = 20
    localparam VN_WIDTH = 5;  // Max 20 points per voxel

    wire hash_found;
    wire hash_busy;
    wire hash_table_full;
    wire [HASH_ADDR_WIDTH-1:0] hash_out_idx;
    wire [VN_WIDTH-1:0] hash_out_point_number;


    hash_table #(
        .COORD_WIDTH(VOXEL_WIDTH),
        .TABLE_SIZE(HASH_TABLE_SIZE),
        .ADDR_WIDTH(HASH_ADDR_WIDTH),
        .MAX_VOXEL_NUM(MAX_VOXEL_NUM),
        .VN_WIDTH(VN_WIDTH),
        .LIFE_CYCLE(16'd100),  // 经过 50 次由于其他写操作导致的时间流逝后过期
        .TIMER_WIDTH(AXIS_ADDR_WIDTH)  // 计时器足够大，防止频繁溢出回绕问题
    ) u_hash_table_tombstone (
        .clk      (clk),
        .rst_n    (rst_n),
        .req_valid(hash_req_valid),
        .req_op   (hash_req_op),
        .key_x    (voxel_x),
        .key_y    (voxel_y),

        .busy                (hash_busy),
        .found               (hash_found),
        .out_idx             (hash_out_idx),           // 0~127
        .out_point_number    (hash_out_point_number),  //1~20
        .table_full          (hash_table_full),
        .m_axis_expire_tready(m_axis_expire_tready),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tdata (m_axis_expire_tdata)
    );
    // ------------------------------------------------------------
    // 3. BRAM Native Write Logic (Replaces AXI-Lite Logic)
    // ------------------------------------------------------------

    // 3.1 线性索引计算
    // Linear Index = (Voxel_Index * 20) + Point_Offset
    // 最大值 approx (128 * 20 - 1) = (2560 - 1) = 11 bits
    // wire [11:0] orign_addr; // 之前宽度为64时的地址
    // assign orign_addr = (hash_out_idx * MAX_POINT_NUM) + hash_out_point_number;

    // 3.2 地址与槽位计算 (Mapping 64 -> 256)
    // Row Address = Linear_Index / 4 (右移2位)
    // wire [BRAM_ADDR_WIDTH-1:0] bram_row_addr = linear_index[11:2]; 
    localparam EXPEND_VOXEL_ROW = MAX_VOXEL_NUM >> 2;  // 20 / 4 = 5
    wire [BRAM_ADDR_WIDTH-1:0] bram_row_addr = hash_out_idx * EXPEND_VOXEL_ROW;  // NOTE
    // Sub-slot Index = Linear_Index % 4 (取低2位)
    wire [1:0] bram_slot_idx = hash_out_point_number[1:0];  // NOTE
    // wire [1:0] bram_slot_idx = linear_index[1:0]; // 0-3


    // 3.3 数据拼接 (Data Replication)
    // 将 64-bit 数据复制 4 份填满 256-bit
    assign bram_wrdata = {4{point_proc}};

    // 3.4 时钟与复位
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;

    // ------------------------------------------------------------
    // 4. State Machine (Simplified)
    // ------------------------------------------------------------
    localparam ST_IN = 3'd0;
    localparam ST_PREP = 3'd1;
    localparam ST_DROP = 3'd2;
    localparam ST_WRITE = 3'd3;  // New state: Single cycle write

    reg [2:0] state;
    reg [$clog2(PRE_LAT)-1:0] pre_cnt;
    wire s_fire = S_AXIS_DRAM_TVALID && S_AXIS_DRAM_TREADY;

    always @(posedge clk) begin
        if (!rst_n) begin
            S_AXIS_DRAM_TREADY <= 1'b1;
            state <= ST_IN;

            point_raw <= 128'd0;
            point_proc <= 64'd0;  // Fixed width to 64

            // Reset BRAM signals
            bram_wr <= 1'b0;
            bram_bwen <= {BRAM_DATA_WIDTH / 8{1'b0}};
            bram_addr <= {BRAM_ADDR_WIDTH{1'b0}};

            pre_cnt <= 'd0;
        end else begin
            case (state)
                ST_IN: begin
                    S_AXIS_DRAM_TREADY <= 1'b1;

                    // Clear Write Signals
                    bram_wr <= 1'b0;
                    bram_bwen <= 0;

                    pre_cnt <= 'd0;
                    hash_req_op <= 1'b1;  // Write mode
                    hash_req_valid <= 1'b0;

                    if (s_fire) begin
                        point_raw <= S_AXIS_DRAM_TDATA;
                        S_AXIS_DRAM_TREADY <= 1'b0;
                        state <= ST_PREP;
                    end
                end

                ST_PREP: begin
                    if (pre_cnt < PRE_LAT) begin
                        pre_cnt <= 'd0;
                        // Data Packing
                        point_proc <= {pt_x_fix16, pt_y_fix16, pt_z_fix16, pt_intensity_fix16};

                        if (keep_point) begin
                            if (hash_found && !hash_busy) begin
                                // --- BRAM Write Setup ---
                                // 核心逻辑：立即准备写入，无需等待握手
                                bram_wr <= 1'b1;
                                bram_addr <= bram_row_addr;
                                // 动态生成 Byte Enable: 只激活 32字节中的某8个字节
                                // 8'hFF 对应 64-bit 的全 1 写使能
                                bram_bwen <= bram_slot_idx == 2'd0 ? (32'hFF000000) : // 插入第四个点
                                bram_slot_idx == 2'd1 ? (32'h000000FF) :
                                            bram_slot_idx == 2'd2 ? (32'h0000FF00) :
                                            bram_slot_idx == 2'd3 ? (32'h00FF0000) : bram_bwen;
                                hash_req_valid <= 1'b0;
                                state <= ST_WRITE;
                            end else begin
                                // Wait for hash table
                                hash_req_valid <= 1'b1;
                                state <= ST_PREP;
                            end
                        end else begin
                            state <= ST_DROP;
                        end
                    end else begin
                        pre_cnt <= pre_cnt + 1'b1;
                    end
                end

                ST_DROP: begin
                    state <= ST_IN;
                    S_AXIS_DRAM_TREADY <= 1'b1;
                end

                ST_WRITE: begin
                    bram_wr <= 1'b0;
                    bram_bwen <= 0;
                    state <= ST_IN;
                    S_AXIS_DRAM_TREADY <= 1'b1;
                end

                default: begin
                    state <= ST_IN;
                    S_AXIS_DRAM_TREADY <= 1'b1;
                end

            endcase
        end
    end

endmodule
