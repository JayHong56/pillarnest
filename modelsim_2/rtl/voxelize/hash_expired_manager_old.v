module hash_expire_manager #(
    parameter         COORD_WIDTH       = 11,
    parameter         VN_WIDTH          = 5,
    parameter         TIMER_WIDTH       = 16,
    parameter         ADDR_WIDTH        = 8,                                                       // 8 -> 256 slots
    parameter         LIFE_CYCLE        = 16'd100,
    parameter         TABLE_SIZE        = 256,
    parameter         BUCKET_AW         = 6,
    parameter         BUCKET_SLOT_WIDTH = 2,                                                       // 4 slots per bucket
    parameter         ENTRY_WIDTH       = 2 + COORD_WIDTH + COORD_WIDTH + VN_WIDTH + TIMER_WIDTH,
    parameter integer BRAM_DATA_WIDTH   = 640,                                                     // 10 * 64
    parameter integer BRAM_ADDR_WIDTH   = 9                                                        // 256pillar * 2brams
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         write_commit,    // 1-cycle pulse when main path commits a write/update
    input  wire [       ADDR_WIDTH-1:0] write_addr,      // the slot address that was written
    input  wire [      TIMER_WIDTH-1:0] time_now,        // current global_timer value (consistent usage)
    output reg  [        BUCKET_AW-1:0] a_addr_shadow,
    output reg  [BUCKET_SLOT_WIDTH-1:0] a_we_shadow,
    input  wire [      ENTRY_WIDTH-1:0] a_rdata_shadow,
    output reg  [      ENTRY_WIDTH-1:0] b_wdata,
    output reg  [        BUCKET_AW-1:0] b_addr,
    output reg  [BUCKET_SLOT_WIDTH-1:0] b_we,
    output reg                          kill_valid,
    output wire                         kill_expired,

    output wire                         bram_expire_clk_a,
    // output wire                          bram_expire_rst_a,
    // output wire                          bram_expire_wr_a,
    // output reg   [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_a,
    output wire [  BRAM_ADDR_WIDTH-1:0] bram_expire_addr_a,
    input  wire [  BRAM_DATA_WIDTH-1:0] bram_expire_rdata_a,
    output wire                         bram_expire_clk_b,
    output wire                         bram_expire_rst_b,
    output wire                         bram_expire_wr_b,
    output reg  [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_b,
    output reg  [  BRAM_ADDR_WIDTH-1:0] bram_expire_addr_b,
    output reg  [  BRAM_DATA_WIDTH-1:0] bram_expire_wrdata_b,

    // ---- AXI-stream out (expired events) ----
    output wire                                              m_axis_expire_tvalid,
    input  wire                                              m_axis_expire_tready,
    output wire [2*COORD_WIDTH+BRAM_ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata
);
    assign bram_expire_clk_a = clk;
    // assign bram_expire_rst_a = ~rst_n;
    assign bram_expire_clk_b = clk;
    assign bram_expire_rst_b = ~rst_n;
    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;

    localparam integer EW = 2 * COORD_WIDTH + BRAM_ADDR_WIDTH + VN_WIDTH;
    wire          fifo_in_ready;
    reg           fifo_in_valid;
    reg  [EW-1:0] fifo_in_data;
    wire          fifo_out_valid;
    wire [EW-1:0] fifo_out_data;
    hash_expire_fifo_sync #(  // fifo缓存expired事件等待PFN处理
        .WIDTH(EW),
        .DEPTH(32)
    ) u_hash_expire_fifo_sync (
        .clk  (clk),
        .rst_n(rst_n),

        .in_valid(fifo_in_valid),
        .in_ready(fifo_in_ready),
        .in_data (fifo_in_data),

        .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready),
        .out_data (fifo_out_data),

        .level()
    );
    assign fifo_out_ready = m_axis_expire_tready;
    assign m_axis_expire_tvalid = fifo_out_valid;
    assign m_axis_expire_tdata = fifo_out_data;


    localparam integer DQ_DEPTH = LIFE_CYCLE;
    reg [ADDR_WIDTH-1:0] dq_mem[0:DQ_DEPTH-1];
    reg [$clog2(DQ_DEPTH)-1:0] dq_wr_ptr, dq_rd_ptr;
    reg     [$clog2(DQ_DEPTH+1)-1:0] dq_count;
    reg                              cand_valid;
    reg     [        ADDR_WIDTH-1:0] cand_addr;

    integer                          k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dq_wr_ptr  <= {($clog2(DQ_DEPTH)) {1'b0}};
            dq_rd_ptr  <= {($clog2(DQ_DEPTH)) {1'b0}};
            dq_count   <= {($clog2(DQ_DEPTH + 1)) {1'b0}};
            cand_valid <= 1'b0;
            cand_addr  <= {ADDR_WIDTH{1'b0}};
            for (k = 0; k < DQ_DEPTH; k = k + 1) begin
                dq_mem[k] <= {ADDR_WIDTH{1'b0}};
            end
        end else begin
            if (write_commit) begin
                dq_mem[dq_wr_ptr] <= write_addr;
                dq_wr_ptr <= (dq_wr_ptr == DQ_DEPTH - 1) ? {($clog2(DQ_DEPTH)) {1'b0}} : (dq_wr_ptr + 1'b1);

                if (dq_count == DQ_DEPTH-1) begin   // 待在dq中的周期数为DQ_DEPTH，将对其处理（判断过期）
                    cand_addr  <= dq_mem[dq_rd_ptr];
                    cand_valid <= 1'b1;
                    dq_rd_ptr  <= (dq_rd_ptr == DQ_DEPTH - 1) ? {($clog2(DQ_DEPTH)) {1'b0}} : (dq_rd_ptr + 1'b1);
                end else begin
                    dq_count   <= dq_count + 1'b1;  // 每次commit自加1
                    cand_valid <= 1'b0;
                end
            end else begin
                cand_valid <= 1'b0;
                cand_addr  <= {ADDR_WIDTH{1'b0}};
            end
        end
    end

    reg write_commit_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_commit_delay <= 1'b0;
        end else if (write_commit) begin
            write_commit_delay <= 1'b1;
        end
    end
    wire write_commit_delayed = write_commit | write_commit_delay;   // 延迟一个周期，确保地址稳定在write_addr上
    reg s0_valid;
    reg [ADDR_WIDTH-1:0] s0_addr;
    reg [TIMER_WIDTH-1:0] s0_time;
    reg s1_valid;
    reg [ADDR_WIDTH-1:0] s1_addr;
    reg [TIMER_WIDTH-1:0] s1_time;
    reg [BUCKET_SLOT_WIDTH-1:0] s0_we;

    wire [1:0] r_status;
    wire signed [COORD_WIDTH-1:0] r_key_x;
    wire signed [COORD_WIDTH-1:0] r_key_y;
    wire [VN_WIDTH-1:0] r_pn;
    wire [TIMER_WIDTH-1:0] r_ts;

    assign {r_status, r_key_x, r_key_y, r_pn, r_ts} = a_rdata_shadow;


    // fifo pop bram 2-stage pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_addr_shadow <= {BUCKET_AW{1'b0}};
            b_wdata       <= {ENTRY_WIDTH{1'b0}};
            s0_valid      <= 1'b0;
            s0_addr       <= {ADDR_WIDTH{1'b0}};
            s0_time       <= {TIMER_WIDTH{1'b0}};
            s1_valid      <= 1'b0;
            s1_addr       <= {ADDR_WIDTH{1'b0}};
            s1_time       <= {TIMER_WIDTH{1'b0}};
            s0_we         <= {BUCKET_SLOT_WIDTH{1'b0}};
        end else if (write_commit_delayed) begin
            s1_valid <= s0_valid;
            s1_addr <= s0_addr;
            s1_time <= s0_time;
            a_we_shadow <= s0_we;  // NOTE: shadow read enable inside the cycle after s0 is set

            s0_valid <= cand_valid;
            s0_addr <= cand_addr;
            s0_time <= time_now;

            if (cand_valid) begin
                a_addr_shadow <= cand_addr[(ADDR_WIDTH-1)-:BUCKET_AW];
                s0_we <= cand_addr[BUCKET_SLOT_WIDTH-1:0];
            end
        end
    end
    localparam [23:0] MAX_VOXEL_NUM = 24'd20;  // 每体素最多 20 点
    localparam integer PT_WIDTH = 16;
    localparam integer POINTS_PER_ROW = BRAM_DATA_WIDTH / (4 * PT_WIDTH);  // 640/64 = 10
    localparam integer EXPEND_VOXEL_ROW = (MAX_VOXEL_NUM + POINTS_PER_ROW - 1) / POINTS_PER_ROW;  // ceil(20/10)=2

    wire [TIMER_WIDTH-1:0] ts_reg = s1_valid ? (s1_time - r_ts) : {TIMER_WIDTH{1'b0}};
    wire expired = (r_status == ST_OCCU) && (ts_reg > LIFE_CYCLE);
    assign kill_expired = expired;
    // wire [BRAM_ADDR_WIDTH-1:0] bram_expire_row_addr = (s1_addr * EXPEND_VOXEL_ROW) + (r_pn / POINTS_PER_ROW);
    // assign bram_expire_addr_a = expired ? bram_expire_row_addr : {BRAM_ADDR_WIDTH{1'b0}};

    // -------------------------------------------------------------------------
    // BRAM A to BRAM B 搬运 Pipeline & 环形覆盖缓存设计
    // -------------------------------------------------------------------------

    // BRAM B 的环形写指针
    reg  [BRAM_ADDR_WIDTH-1:0] bram_b_wr_ptr;

    // 用于控制连续读 2 行的流水线寄存器
    reg  [BRAM_ADDR_WIDTH-1:0] bram_read_addr_1;
    reg                        bram_read_cycle_1;
    reg                        we_delay_1;
    reg                        we_delay_2;
    reg                        bram_expire_wr_b_reg;

    // 第 1 行的基准地址
    wire [BRAM_ADDR_WIDTH-1:0] base_row_addr = s1_addr * EXPEND_VOXEL_ROW;
    // BRAM A 读地址 MUX：Cycle 0 读第 1 行，Cycle 1 读第 2 行
    assign bram_expire_addr_a = (s1_valid && expired) ? base_row_addr :
                                (bram_read_cycle_1)     ? bram_read_addr_1 :
                                {BRAM_ADDR_WIDTH{1'b0}};
    // 假设本模块只读 A，不写 A
    assign bram_expire_wr_a = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_read_cycle_1    <= 1'b0;
            bram_read_addr_1     <= {BRAM_ADDR_WIDTH{1'b0}};
            we_delay_1           <= 1'b0;
            we_delay_2           <= 1'b0;
            bram_b_wr_ptr        <= {BRAM_ADDR_WIDTH{1'b0}};
            bram_expire_wrdata_b <= {BRAM_DATA_WIDTH{1'b0}};
            bram_expire_addr_b   <= {BRAM_ADDR_WIDTH{1'b0}};
            bram_expire_bwen_b   <= {(BRAM_DATA_WIDTH / 8) {1'b0}};
            bram_expire_wr_b_reg <= 1'b0;
        end else begin
            // --- 阶段 1：生成 BRAM A 第 2 行的读请求 ---
            if (s1_valid && expired) begin
                bram_read_cycle_1 <= 1'b1;
                bram_read_addr_1  <= base_row_addr + 1'b1;  // 暂存第 2 行的地址
            end else begin
                bram_read_cycle_1 <= 1'b0;
            end

            // --- 阶段 2：数据到达延迟打拍 (匹配 BRAM A 的 1 cycle 读延迟) ---
            we_delay_1 <= (s1_valid && expired);
            we_delay_2 <= we_delay_1;

            // --- 阶段 3：捕获 BRAM A 数据并写入 BRAM B ---
            if (we_delay_1 || we_delay_2) begin
                bram_expire_wrdata_b <= bram_expire_rdata_a;  // 获取 BRAM A 读出的数据
                bram_expire_addr_b   <= bram_b_wr_ptr;  // 写入 BRAM B 当前指针位置
                bram_expire_bwen_b   <= {(BRAM_DATA_WIDTH / 8) {1'b1}};  // 全字节使能写入

                // 指针递增，加满自动溢出归零，实现环形覆盖
                bram_b_wr_ptr        <= bram_b_wr_ptr + 1'b1;
            end else begin
                bram_expire_bwen_b <= {(BRAM_DATA_WIDTH / 8) {1'b0}};
            end

            // 寄存写使能信号，使其与地址、数据在同一时钟周期对齐
            bram_expire_wr_b_reg <= (we_delay_1 || we_delay_2);
        end
    end
    // 输出 BRAM B 写使能
    assign bram_expire_wr_b = bram_expire_wr_b_reg;

    // 修改 2：设计 2 周期的事件延迟 FIFO Push 流水线，保证数据写完 BRAM B 才通知 pfe
    reg fifo_push_valid_d1, fifo_push_valid_d2;
    reg [EW-1:0] fifo_push_data_d1, fifo_push_data_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_push_valid_d1 <= 1'b0;
            fifo_push_valid_d2 <= 1'b0;
            fifo_in_valid      <= 1'b0;
        end else begin
            // Cycle 0: 捕获 expired，以及此时 BRAM B 的基准写入地址
            // (此时 bram_b_wr_ptr 还没自加，恰好是接下来两行写入的首地址！)
            fifo_push_valid_d1 <= (s1_valid && expired);
            fifo_push_data_d1  <= {r_key_x, r_key_y, bram_b_wr_ptr, r_pn};

            // Cycle 1: BRAM A 读第一行
            fifo_push_valid_d2 <= fifo_push_valid_d1;
            fifo_push_data_d2  <= fifo_push_data_d1;

            // Cycle 2: 发起向 FIFO 的推入，此时 BRAM B 的管线(we_delay_2)也刚好开始写入最后一行
            if (fifo_push_valid_d2 && fifo_in_ready) begin
                fifo_in_valid <= 1'b1;
                fifo_in_data  <= fifo_push_data_d2;
            end else begin
                fifo_in_valid <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kill_valid <= 1'b0;
        end else begin
            if (s1_valid && expired) begin  // 确定expired，将数据送入fifo，给出墓碑
                kill_valid <= 1'b1;
                b_we <= s1_addr[BUCKET_SLOT_WIDTH-1:0];
                b_addr <= s1_addr[ADDR_WIDTH-1-:BUCKET_AW];
                b_wdata <= {ST_TOMB, {COORD_WIDTH{1'b0}}, {COORD_WIDTH{1'b0}}, {VN_WIDTH{1'b0}}, {TIMER_WIDTH{1'b0}}};
            end else begin
                kill_valid <= 1'b0;
            end
        end
    end

endmodule
