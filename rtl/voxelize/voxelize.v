// =========================================================================
// AXI4-Stream 封装的 Voxelize 处理器顶层
// =========================================================================
module voxelize #(
    // AXI4 总线数据位宽
    parameter integer AXIS_DATA_WIDTH     = 128,
    parameter integer DRAM_DATA_WIDTH     = 128,
    parameter integer DRAM_ADDR_WIDTH     = 18,
    // 内部存储配置
    parameter integer BRAM_DATA_WIDTH     = 640,
    parameter integer BRAM_ADDR_WIDTH     = 9,
    parameter integer BRAM_ADDR_WIDTH_PFE = 6,
    // 权重与偏置文件（移至参数区，避免硬编码）
    parameter         MEM_WEIGHT_FILE     = "E:\\verilog\\board\\.parameters\\pfn_weight.mem",
    parameter         MEM_BIAS_FILE       = "E:\\verilog\\board\\.parameters\\bias.mem"
) (
    // 全局时钟与复位
    input  wire                         aclk,
    input  wire                         aresetn,
    // --- 新增：由 AXI-Lite 传入的动态配置端口 ---
    input  wire [                 31:0] base_addr_in,
    input  wire [                 22:0] frame_bytes_in,
    // -----------------------------------------------------------
    // AXI4-Stream Slave（点云数据输入）
    // -----------------------------------------------------------
    input  wire [  AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [AXIS_DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  wire                         s_axis_tlast,        // 外部传入的一帧最后一个点标志
    // -----------------------------------------------------------
    // AXI4-Stream Master（输出 Voxel 特征）
    // -----------------------------------------------------------
    output wire [  AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire                         m_axis_tvalid,
    output wire [AXIS_DATA_WIDTH/8-1:0] m_axis_tkeep,        // 新增 TKEEP 信号
    input  wire                         m_axis_tready,       // 内部暂不支持背压，先预留
    output wire                         m_axis_tlast,        // 整帧处理彻底结束（由 flush_done 驱动）
    // 侧边通道输出（Voxel 坐标与有效标志）
    output wire [               11-1:0] m_axis_voxel_x,
    output wire [               11-1:0] m_axis_voxel_y,
    output wire                         m_axis_voxel_valid,
    // 启动命令接口（由外部控制器触发一次完整的命令发送流程）
    input  wire                         start_req,           // 上升沿触发一次命令发送操作
    output reg                          idle,                // 模块是否处于空闲状态
    // -----------------------------------------------------------
    // AXI-Stream Command Interface（连接到 DataMover 的 S_AXIS_MM2S_CMD）
    // -----------------------------------------------------------
    output wire                         m_axis_cmd_tvalid,
    input  wire                         m_axis_cmd_tready,
    output wire [                 71:0] m_axis_cmd_tdata
);

    // 时钟、复位内部映射
    wire        clk_p = aclk;
    wire        rst_n = aresetn;

    // =========================================================================
    // 帧尾信号（Frame End）生成与延迟补偿
    // =========================================================================
    // s_axis_tlast 在最后一个点完成握手时触发
    wire        frame_end_raw = s_axis_tvalid && s_axis_tready && s_axis_tlast;

    reg  [63:0] frame_end_shift;
    wire        hash_stall;
    always @(posedge clk_p or negedge rst_n) begin
        if (!rst_n) begin
            frame_end_shift <= 64'd0;
        end else if (!hash_stall) begin
            frame_end_shift <= {frame_end_shift[62:0], frame_end_raw};
        end
    end

    // 补偿 AXI 流水线深度：具体拍数需根据内部接收流水线长度确定
    wire frame_end = frame_end_shift[30];

    // =========================================================================
    // 内部连线声明
    // =========================================================================
    localparam COORD_WIDTH = 11;
    localparam PT_WIDTH = 16;
    localparam VN_WIDTH = 5;
    localparam EXPAND_PT_DIM = 11;  // x,y,z,intensity,0,(x-mean,y-mean,z-mean,intensity-mean),(x-vmean,y-vmean,z-vmean,intensity-vmean)
    localparam OUT_PT_DIM = 48;
    localparam MAX_VOXEL_NUM = 12'd20;
    localparam HASH_TABLE_SIZE = 256;
    localparam HASH_ADDR_WIDTH = $clog2(HASH_TABLE_SIZE);
    localparam [15:0] THRESHOLD_CLOSE = 16'h0100;  // 1.00m
    localparam [15:0] THRESHOLD_BOUDARY = 16'h3600;  // 54.00m
    localparam [15:0] THRESHOLD_BOUDARY_Z_LOW = 16'h5000;  // +5m (-5m)
    localparam [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h3000;  // +3m
    localparam integer PRE_LAT = 0;  // 预处理固定延迟（拍数占位）
    localparam [15:0] LIFE_CYCLE = 16'd100;
    wire                                                         flush_done;

    wire                                                         bram_voxelpoint_clk;
    wire                                                         bram_voxelpoint_wr;
    wire        [                         BRAM_DATA_WIDTH/8-1:0] bram_voxelpoint_bwen;
    wire        [                           BRAM_ADDR_WIDTH-1:0] bram_voxelpoint_addr;
    wire        [                           BRAM_DATA_WIDTH-1:0] bram_voxelpoint_wrdata;

    wire                                                         bram_expire_clk_a;
    wire        [                           BRAM_ADDR_WIDTH-1:0] bram_expire_addr_a;
    wire        [                           BRAM_DATA_WIDTH-1:0] bram_expire_rdata_a;

    wire                                                         bram_expire_clk_b;
    wire                                                         bram_expire_wr_b;
    wire        [                         BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_b;
    wire        [                       BRAM_ADDR_WIDTH_PFE-1:0] bram_expire_addr_b;
    wire        [                           BRAM_DATA_WIDTH-1:0] bram_expire_wrdata_b;

    wire                                                         bram_pfe_clk;
    wire        [                       BRAM_ADDR_WIDTH_PFE-1:0] bram_pfe_addr;
    wire        [                           BRAM_DATA_WIDTH-1:0] bram_pfe_rdata;

    wire                                                         m_axis_expire_tvalid;
    wire                                                         m_axis_expire_tready;
    wire        [2*COORD_WIDTH+BRAM_ADDR_WIDTH_PFE+VN_WIDTH-1:0] m_axis_expire_tdata;

    wire                                                         m_axis_pfe_valid;
    wire                                                         m_axis_pfe_tready;
    wire        [                    EXPAND_PT_DIM*PT_WIDTH-1:0] m_axis_pfe_data;
    wire                                                         m_axis_pfe_last;
    wire                                                         m_axis_pfe_voxel_valid;
    wire signed [                               COORD_WIDTH-1:0] m_axis_pfe_voxel_x;
    wire signed [                               COORD_WIDTH-1:0] m_axis_pfe_voxel_y;
    wire                                                         m_axis_pfe_flush_done;

    wire                                                         m_axis_pfn_voxel_valid;
    wire signed [                               COORD_WIDTH-1:0] m_axis_pfn_voxel_x;
    wire signed [                               COORD_WIDTH-1:0] m_axis_pfn_voxel_y;
    wire                                                         m_axis_pfn_valid;
    wire        [                           AXIS_DATA_WIDTH-1:0] m_axis_out_data;
    wire        [                       OUT_PT_DIM*PT_WIDTH-1:0] m_axis_pfn_data;
    wire                                                         m_axis_out_flush_done;
    wire                                                         m_axis_pfn_tready;
    wire                                                         m_axis_out_tready;
    assign m_axis_out_tready = m_axis_tready;

    // =========================================================================
    // 核心模块实例化
    // =========================================================================
    voxel_coor_pipe #(
        .DRAM_DATA_WIDTH         (DRAM_DATA_WIDTH),
        .DRAM_ADDR_WIDTH         (DRAM_ADDR_WIDTH),
        .BRAM_DATA_WIDTH         (BRAM_DATA_WIDTH),
        .BRAM_ADDR_WIDTH         (BRAM_ADDR_WIDTH),
        .BRAM_ADDR_WIDTH_PFE     (BRAM_ADDR_WIDTH_PFE),
        .HASH_ADDR_WIDTH         (HASH_ADDR_WIDTH),
        .THRESHOLD_CLOSE         (THRESHOLD_CLOSE),
        .THRESHOLD_BOUDARY       (THRESHOLD_BOUDARY),
        .THRESHOLD_BOUDARY_Z_LOW (THRESHOLD_BOUDARY_Z_LOW),
        .THRESHOLD_BOUDARY_Z_HIGH(THRESHOLD_BOUDARY_Z_HIGH),
        .PRE_LAT                 (PRE_LAT),
        .LIFE_CYCLE              (LIFE_CYCLE)
    ) voxel_coordinate_inst (
        .clk              (clk_p),
        .rst_n            (rst_n),
        .frame_end        (frame_end),
        .flush_done       (flush_done),
        .hash_stall       (hash_stall),
        // AXI Stream Slave（直接接入顶层输入总线）
        .s_axis_dram_data (s_axis_tdata),
        .s_axis_dram_keep (s_axis_tkeep),               // 可忽略
        .s_axis_dram_last (s_axis_tlast),
        .s_axis_dram_valid(s_axis_tvalid),
        .s_axis_dram_ready(s_axis_tready),

        .bram_voxelpoint_clk   (bram_voxelpoint_clk),
        .bram_voxelpoint_rst   (),
        .bram_voxelpoint_wr    (bram_voxelpoint_wr),
        .bram_voxelpoint_bwen  (bram_voxelpoint_bwen),
        .bram_voxelpoint_addr  (bram_voxelpoint_addr),
        .bram_voxelpoint_wrdata(bram_voxelpoint_wrdata),

        .bram_expire_clk_a   (bram_expire_clk_a),
        .bram_expire_addr_a  (bram_expire_addr_a),
        .bram_expire_rdata_a (bram_expire_rdata_a),
        .bram_expire_clk_b   (bram_expire_clk_b),
        .bram_expire_rst_b   (),
        .bram_expire_wr_b    (bram_expire_wr_b),
        .bram_expire_bwen_b  (bram_expire_bwen_b),
        .bram_expire_addr_b  (bram_expire_addr_b),
        .bram_expire_wrdata_b(bram_expire_wrdata_b),

        .m_axis_expire_tdata (m_axis_expire_tdata),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tready(m_axis_expire_tready)
    );

    pfe #(
        .COORD_WIDTH        (COORD_WIDTH),
        .PT_WIDTH           (PT_WIDTH),
        .MAX_VOXEL_NUM      (MAX_VOXEL_NUM),
        .VN_WIDTH           (VN_WIDTH),
        .EXPAND_PT_DIM      (EXPAND_PT_DIM),
        .BRAM_DATA_WIDTH    (BRAM_DATA_WIDTH),
        .BRAM_ADDR_WIDTH    (BRAM_ADDR_WIDTH),
        .BRAM_ADDR_WIDTH_PFE(BRAM_ADDR_WIDTH_PFE)
    ) u_pfe (
        .clk                 (clk_p),
        .rst_n               (rst_n),
        .s_axis_expire_tvalid(m_axis_expire_tvalid),
        .s_axis_expire_tready(m_axis_expire_tready),
        .s_axis_expire_tdata (m_axis_expire_tdata),

        .bram_pfe_clk  (bram_pfe_clk),
        .bram_pfe_addr (bram_pfe_addr),
        .bram_pfe_rdata(bram_pfe_rdata),

        .m_axis_pfe_valid      (m_axis_pfe_valid),
        .m_axis_pfe_tready     (m_axis_pfe_tready),
        .m_axis_pfe_data       (m_axis_pfe_data),
        .m_axis_pfe_last       (m_axis_pfe_last),
        .m_axis_pfe_voxel_valid(m_axis_pfe_voxel_valid),
        .m_axis_pfe_voxel_x    (m_axis_pfe_voxel_x),
        .m_axis_pfe_voxel_y    (m_axis_pfe_voxel_y),
        .m_axis_pfe_flush_done (m_axis_pfe_flush_done),
        .flush_done            (flush_done)
    );

    pfn_layer #(
        .EXPAND_PT_DIM  (EXPAND_PT_DIM),
        .COORD_WIDTH    (COORD_WIDTH),
        .OUT_PT_DIM     (OUT_PT_DIM),
        .PT_WIDTH       (PT_WIDTH),
        .MEM_WEIGHT_FILE(MEM_WEIGHT_FILE),
        .MEM_BIAS_FILE  (MEM_BIAS_FILE),
        .WEIGHT_WIDTH   (16),
        .ACC_WIDTH      (32)
    ) u_pfn_layer (
        .clk                       (clk_p),
        .rst_n                     (rst_n),
        .s_axis_pfe_valid          (m_axis_pfe_valid),
        .s_axis_pfe_tready         (m_axis_pfe_tready),
        .s_axis_pfe_data           (m_axis_pfe_data),
        .s_axis_pfe_last           (m_axis_pfe_last),
        .s_axis_pfe_voxel_valid    (m_axis_pfe_voxel_valid),
        .s_axis_pfe_voxel_x        (m_axis_pfe_voxel_x),
        .s_axis_pfe_voxel_y        (m_axis_pfe_voxel_y),
        .s_axis_pfe_flush_done     (m_axis_pfe_flush_done),
        // pfn
        .m_axis_pfn_voxel_valid_out(m_axis_pfn_voxel_valid),
        .m_axis_pfn_voxel_x        (m_axis_pfn_voxel_x),
        .m_axis_pfn_voxel_y        (m_axis_pfn_voxel_y),
        .m_axis_pfn_valid          (m_axis_pfn_valid),
        .m_axis_pfn_tready         (m_axis_pfn_tready),
        .m_axis_pfn_data           (m_axis_pfn_data),
        .m_axis_pfn_flush_done     (m_axis_pfn_flush_done)
    );

    wire [AXIS_DATA_WIDTH-1:0] m_axis_out_tdata;
    pfn_width_converter #(
        .IN_WIDTH (OUT_PT_DIM * PT_WIDTH),
        .OUT_WIDTH(AXIS_DATA_WIDTH)
    ) u_pfn_width_converter (
        .clk              (clk_p),
        .rst_n            (rst_n),
        .s_axis_pfn_tvalid(m_axis_pfn_valid),
        .s_axis_pfn_tready(m_axis_pfn_tready),
        .s_axis_pfn_tdata (m_axis_pfn_data),
        .m_axis_out_tvalid(m_axis_out_tvalid),
        .m_axis_out_tready(m_axis_out_tready),
        .m_axis_out_tdata (m_axis_out_tdata),
        .m_axis_out_tlast (m_axis_out_tlast)
    );


    // =========================================================================
    // 内部 BRAM 实例化（保持原样）
    // =========================================================================
    dualport_bram #(
        .DATA_WIDTH(BRAM_DATA_WIDTH),
        .ADDR_WIDTH(BRAM_ADDR_WIDTH),
        .MEM_FILE  ("NOTHING")
    ) u_voxelpoint_bram (
        .a_clk (bram_voxelpoint_clk),
        .a_wr  (bram_voxelpoint_wr),
        .a_en  (1'b1),
        .a_bwen(bram_voxelpoint_bwen),
        .a_addr(bram_voxelpoint_addr),
        .a_din (bram_voxelpoint_wrdata),
        .a_dout(),
        .b_clk (bram_expire_clk_a),
        .b_wr  (1'b0),
        .b_en  (1'b1),
        .b_bwen(1'b0),
        .b_addr(bram_expire_addr_a),
        .b_din (),
        .b_dout(bram_expire_rdata_a)
    );

    dualport_bram #(
        .DATA_WIDTH(BRAM_DATA_WIDTH),
        .ADDR_WIDTH(BRAM_ADDR_WIDTH_PFE),
        .MEM_FILE  ("NOTHING")
    ) u_pfe_bram (
        .a_clk (bram_expire_clk_b),
        .a_wr  (bram_expire_wr_b),
        .a_en  (1'b1),
        .a_bwen(bram_expire_bwen_b),
        .a_addr(bram_expire_addr_b),
        .a_din (bram_expire_wrdata_b),
        .a_dout(),
        .b_clk (bram_pfe_clk),
        .b_wr  (1'b0),
        .b_en  (1'b1),
        .b_bwen(1'b0),
        .b_addr(bram_pfe_addr),
        .b_din (),
        .b_dout(bram_pfe_rdata)
    );

    // =========================================================================
    // AXI4-Stream 输出信号映射
    // =========================================================================
    // 当前输出数据宽度与 AXIS_DATA_WIDTH 一致，因此直接透传
    // 若后续存在不足位宽的情况，可通过 TKEEP 指示有效字节

    assign m_axis_tdata       = m_axis_out_tdata;
    assign m_axis_tkeep       = {(AXIS_DATA_WIDTH / 8) {1'b1}};
    assign m_axis_tvalid      = m_axis_out_tvalid;
    assign m_axis_tlast       = m_axis_out_tlast;

    assign m_axis_voxel_x     = m_axis_pfn_voxel_x;
    assign m_axis_voxel_y     = m_axis_pfn_voxel_y;
    assign m_axis_voxel_valid = m_axis_pfn_voxel_valid;


    reg valid_reg;
    reg start_d1;
    // 上升沿检测
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            start_d1 <= 1'b0;
        end else begin
            start_d1 <= start_req;
        end
    end
    wire start_pulse = start_req && !start_d1;

    // =======================================================
    // 拼装 AXI DataMover MM2S Command（72-bit 格式）
    // =======================================================
    // [22:0]  BTT  = 本帧总传输字节数（Bytes To Transfer）
    // [23]    Type = 1，表示 INCR 递增突发
    // [29:24] DSA  = 0，Dynamic Source Address
    // [30]    EOF  = 1，传输完成后在 TLAST 位置结束
    // [31]    DRR  = 0，关闭 Data Realignment
    // [63:32] SADDR= 源地址（DDR 物理地址）
    // [67:64] TAG  = 0
    // [71:68] RSVD = 0
    // 这里将原先固定参数替换为动态输入端口
    assign m_axis_cmd_tdata = {
        4'b0000,
        4'b0000,
        base_addr_in,  // 动态传入的源地址
        1'b0,
        1'b1,
        6'b000000,
        1'b1,
        frame_bytes_in  // 动态传入的传输字节数
    };

    assign m_axis_cmd_tvalid = valid_reg;

    // =======================================================
    // 命令发送握手状态机
    // =======================================================
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            valid_reg <= 1'b0;
            idle      <= 1'b1;
        end else begin
            if (idle) begin
                // 收到启动脉冲后，拉高 valid，准备发送命令
                if (start_pulse) begin
                    valid_reg <= 1'b1;
                    idle      <= 1'b0;
                end
            end else begin
                // DataMover 就绪且 valid 为高时，完成一次命令握手
                if (valid_reg && m_axis_cmd_tready) begin
                    valid_reg <= 1'b0;
                    idle      <= 1'b1;  // 命令发送完成，回到空闲态，等待下一次触发
                end
            end
        end
    end


endmodule
