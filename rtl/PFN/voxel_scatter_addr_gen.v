module voxel_scatter_addr_gen #(
    parameter [31:0] BASE_ADDR       = 32'h2000_0000, // DDR 中 Pseudo-Image 的起始基地址
    parameter integer GRID_WIDTH     = 432,           // 伪图像的 X 轴网格数 (根据你的雷达范围计算)
    parameter integer BYTES_PER_VOX  = 96,            // 每个 Voxel 占据的字节数 (768bit / 8)
    parameter integer COORD_WIDTH    = 11
) (
    input  wire                   aclk,
    input  wire                   aresetn,

    // -----------------------------------------------------------
    // 输入：来自你的 voxelize 顶层的坐标信息
    // -----------------------------------------------------------
    input  wire                   s_voxel_valid,
    input  wire [COORD_WIDTH-1:0] s_voxel_x,
    input  wire [COORD_WIDTH-1:0] s_voxel_y,
    // input  wire                s_voxel_last, // 可选：用于生成 EOF

// -----------------------------------------------------------
    // 输出：AXI DataMover 命令总线 (改用标准 AXI-Stream 命名)
    // -----------------------------------------------------------
    output wire                   m_axis_cmd_tvalid,
    input  wire                   m_axis_cmd_tready,
    output wire [71:0]            m_axis_cmd_tdata
);

    wire clk = aclk;
    wire rst_n = aresetn;
    // 内部流水线寄存器
    reg                     valid_d1, valid_d2;
    reg [2*COORD_WIDTH-1:0] linear_idx;
    reg [31:0]              target_addr;

    // 因为坐标可能被视作有符号数，这里转换为无符号数用于地址计算
    // 如果你在 PFE 中已经做了偏移(Offset)对齐，确保进来的 X,Y 是从 0 开始的正整数
    wire [COORD_WIDTH-1:0] ux = s_voxel_x;
    wire [COORD_WIDTH-1:0] uy = s_voxel_y;

    // =======================================================
    // Stage 1: 计算线性索引 (Y * Width + X)
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            linear_idx <= 0;
            valid_d1   <= 0;
        end else begin
            // 假设外部握手成功时才推进（如果 DataMover CMD FIFO 满，需要反压）
            if (m_axis_cmd_tready || !m_axis_cmd_tvalid) begin 
                valid_d1 <= s_voxel_valid;
                if (s_voxel_valid) begin
                    // 乘法器将被综合为 DSP 单元
                    linear_idx <= (uy * GRID_WIDTH) + ux;
                end
            end
        end
    end

    // =======================================================
    // Stage 2: 计算最终物理地址 (Base + Idx * Bytes)
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_addr <= 0;
            valid_d2    <= 0;
        end else begin
            if (m_axis_cmd_tready || !m_axis_cmd_tvalid) begin
                valid_d2 <= valid_d1;
                if (valid_d1) begin
                    // 乘以 96 可以综合为 DSP，或者写成 (linear_idx<<6) + (linear_idx<<5)
                    target_addr <= BASE_ADDR + (linear_idx * BYTES_PER_VOX);
                end
            end
        end
    end

    // =======================================================
    // Stage 3: 拼装 AXI DataMover Command
    // =======================================================
    // DataMover Command Format (32-bit Address):
    // [22:0]  BTT (Bytes To Transfer) = 96
    // [23]    Type (1 = INCR)
    // [31:24] DSA (Dynamic Source Address) / User = 0
    // [32]    EOF (End of Frame) = 1 (每个 Voxel 是独立的一帧写入)
    // [38:33] DRR (Dataroute) = 0
    // [63:39] SADDR/DADDR (32-bit 物理地址的截取) -> 实际上 32位地址版，地址在 [63:32]
    // [67:64] TAG = 0
    // [71:68] RSVD = 0

    wire [22:0] btt  = 23'd96; // 每次固定写入 96 字节
    wire        eof  = 1'b1;   // 每次写完 96 字节后释放总线

    assign m_axis_cmd_tdata[22:0]  = btt;
    assign m_axis_cmd_tdata[23]    = 1'b1; // INCR 模式
    assign m_axis_cmd_tdata[31:24] = 8'd0;
    assign m_axis_cmd_tdata[32]    = eof;
    assign m_axis_cmd_tdata[38:33] = 6'd0;
    // 注意：如果是 32 位地址，DataMover 的高位地址通常拼在这里
    assign m_axis_cmd_tdata[71:39] = {8'd0, target_addr[31:7]}; 
    
    // 为了防止复杂的位拼接导致兼容性问题，更推荐直接按 Xilinx PG022 手册对齐
    wire [71:0] cmd_pack;
    assign cmd_pack[22:0]  = btt;
    assign cmd_pack[23]    = 1'b1; 
    assign cmd_pack[31:24] = 8'd0;
    assign cmd_pack[32]    = eof;
    assign cmd_pack[38:33] = 6'd0;
    assign cmd_pack[63:39] = target_addr[31:7]; // 地址的高位
    assign cmd_pack[67:64] = 4'd0; // TAG
    assign cmd_pack[71:68] = 4'd0;

    // 简化赋值 (取决于你的 Vivado 版本，部分版本命令总线为 104 bit)
    // 这里以最通用的 72-bit (32bit 地址) 为例：
    // [31:0] 低 32 位包含 BTT 等
    // [63:32] 为 32 位 DADDR
    // [71:64] 为 TAG 等控制位
    
    // 正确的 72-bit S2MM Command 拼接 (PG022 S2MM Command):
    wire [31:0] daddr = target_addr;
    wire [22:0] bytes = 23'd96;
    assign m_axis_cmd_tdata = {
        4'b0000,    // [71:68] RSVD
        4'b0000,    // [67:64] TAG
        daddr,      // [63:32] DADDR
        1'b0,       // [31] DRR
        1'b1,       // [30] EOF
        6'b000000,  // [29:24] DSA
        1'b1,       // [23] Type: 1=INCR
        bytes       // [22:0] BTT
    };

    assign m_axis_cmd_tvalid = valid_d2;

endmodule