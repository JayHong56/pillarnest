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
    input wire clk,
    input wire rst_n,
    input wire write_commit,  // 1-cycle pulse when main path commits a write/update
    input wire [ADDR_WIDTH-1:0] write_addr,  // the slot address that was written
    input wire [TIMER_WIDTH-1:0] time_now,  // current global_timer value (consistent usage)
    input wire frame_end,  // 外部传入：当前帧点云结束脉冲 (1-cycle pulse)
    output wire flush_done,  // 输出：哈希表剩余有效点已全部输出完毕
    output reg [BUCKET_AW-1:0] a_addr_shadow,
    output reg [BUCKET_SLOT_WIDTH-1:0] a_we_shadow,
    input wire [ENTRY_WIDTH-1:0] a_rdata_shadow,
    output reg [ENTRY_WIDTH-1:0] b_wdata,
    output reg [BUCKET_AW-1:0] b_addr,
    output reg [BUCKET_SLOT_WIDTH-1:0] b_we,
    output reg kill_valid,
    output wire kill_expired,
    output wire bram_expire_clk_a,
    // output wire                         bram_expire_rst_a,
    // output wire                         bram_expire_wr_a,
    // output reg  [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_a,
    output wire [BRAM_ADDR_WIDTH-1:0] bram_expire_addr_a,
    input wire [BRAM_DATA_WIDTH-1:0] bram_expire_rdata_a,
    output wire bram_expire_clk_b,
    output wire bram_expire_rst_b,
    output reg bram_expire_wr_b,
    output reg [BRAM_DATA_WIDTH/8-1:0] bram_expire_bwen_b,
    output reg [BRAM_ADDR_WIDTH-1:0] bram_expire_addr_b,
    output reg [BRAM_DATA_WIDTH-1:0] bram_expire_wrdata_b,
    // ---- AXI-stream out (expired events) ----
    output wire m_axis_expire_tvalid,
    input wire m_axis_expire_tready,
    output wire [2*COORD_WIDTH+BRAM_ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata,
    // fifo almost full -----backpressure
    output wire hash_stall
);
    assign bram_expire_clk_a = clk;
    // assign bram_expire_rst_a = ~rst_n;
    assign bram_expire_clk_b = clk;
    assign bram_expire_rst_b = ~rst_n;
    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;

    localparam integer EW = 2 * COORD_WIDTH + BRAM_ADDR_WIDTH + VN_WIDTH;
    localparam integer DEPTH = 32;
    wire                     fifo_in_ready;
    reg                      fifo_in_valid;
    reg  [           EW-1:0] fifo_in_data;
    wire                     fifo_out_valid;
    wire [           EW-1:0] fifo_out_data;
    wire [$clog2(DEPTH)-1:0] fifo_out_level;
    hash_expire_fifo_sync #(  // fifo缓存expired事件等待PFN处理
        .WIDTH(EW),
        .DEPTH(DEPTH)
    ) u_hash_expire_fifo_sync (
        .clk  (clk),
        .rst_n(rst_n),

        .in_valid(fifo_in_valid),
        .in_ready(fifo_in_ready),
        .in_data (fifo_in_data),

        .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready),
        .out_data (fifo_out_data),

        .level(fifo_out_level)
    );
    assign fifo_out_ready = m_axis_expire_tready;
    assign m_axis_expire_tvalid = fifo_out_valid;
    assign m_axis_expire_tdata = fifo_out_data;
    assign hash_stall = (fifo_out_level >= (DEPTH / 2));

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
        end else if (frame_end) begin
            // 收到清空指令，直接复位 DQ，因为接下来的 Flush FSM 会兜底扫描全表
            dq_wr_ptr  <= 0;
            dq_rd_ptr  <= 0;
            dq_count   <= 0;
            cand_valid <= 1'b0;

        end else if (write_commit) begin
            dq_mem[dq_wr_ptr] <= write_addr;
            dq_wr_ptr <= (dq_wr_ptr == DQ_DEPTH - 1) ? {($clog2(DQ_DEPTH)) {1'b0}} : (dq_wr_ptr + 1'b1);

            if (dq_count == DQ_DEPTH - 1) begin  // 待在dq中的周期数为DQ_DEPTH，将对其处理（判断过期）
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

    reg write_commit_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_commit_delay <= 1'b0;
        end else if (write_commit) begin
            write_commit_delay <= 1'b1;
        end
    end
    wire write_commit_delayed = write_commit | write_commit_delay;  // 延迟一个周期，确保cand_valid/cand_addr稳定
    reg s0_valid;
    reg [ADDR_WIDTH-1:0] s0_addr;
    reg [TIMER_WIDTH-1:0] s0_time;
    reg s1_valid;
    reg s1_force_expire;  // <--- 新增
    reg [ADDR_WIDTH-1:0] s1_addr;
    reg [TIMER_WIDTH-1:0] s1_time;
    reg [BUCKET_SLOT_WIDTH-1:0] s0_we;
    reg s0_force_expire;  // <--- 新增

    wire [1:0] r_status;
    wire signed [COORD_WIDTH-1:0] r_key_x;
    wire signed [COORD_WIDTH-1:0] r_key_y;
    wire [VN_WIDTH-1:0] r_pn;
    wire [TIMER_WIDTH-1:0] r_ts;
    assign {r_status, r_key_x, r_key_y, r_pn, r_ts} = a_rdata_shadow;

    
    reg flushing;
    reg [ADDR_WIDTH:0] flush_cnt;  // 多一位用于判断结束 (0~256)
    // 控制流水线步进，只有在未扫完且无反压时才工作
    wire flush_run = flushing && (flush_cnt < TABLE_SIZE) && !hash_stall;

    // 动态选择：正常模式吃 DQ 吐出的 cand_addr，Flush 模式吃扫描计数器 flush_cnt
    wire eff_cand_valid = flush_run ? 1'b1 : cand_valid;
    wire [ADDR_WIDTH-1:0] eff_cand_addr = flush_run ? flush_cnt[ADDR_WIDTH-1:0] : cand_addr;
    // 流水线推进条件：正常的写提交脉冲 OR 正在执行强制扫描
    wire pipe_advance = write_commit_delayed | flush_run;

    // fifo pop bram 2-stage pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_addr_shadow   <= {BUCKET_AW{1'b0}};
            s0_valid        <= 1'b0;
            s0_addr         <= {ADDR_WIDTH{1'b0}};
            s0_time         <= {TIMER_WIDTH{1'b0}};
            s1_valid        <= 1'b0;
            s1_addr         <= {ADDR_WIDTH{1'b0}};
            s1_time         <= {TIMER_WIDTH{1'b0}};
            s0_we           <= {BUCKET_SLOT_WIDTH{1'b0}};
            s0_force_expire <= 1'b0;
            s1_force_expire <= 1'b0;

        end else if (pipe_advance) begin
            s1_force_expire <= s0_force_expire;  // <--- 打拍传递强制标志

            s1_valid        <= s0_valid;
            s1_addr         <= s0_addr;
            s1_time         <= s0_time;
            a_we_shadow     <= s0_we;  // NOTE: 这里we信号要比addr晚一个周期给

            s0_valid        <= eff_cand_valid;
            s0_addr         <= eff_cand_addr;
            s0_time         <= time_now;
            s0_force_expire <= flush_run;  // <--- 如果是 Flush 模式塞进来的点，打上“必死”烙印


            if (eff_cand_valid) begin
                a_addr_shadow <= eff_cand_addr[(ADDR_WIDTH-1)-:BUCKET_AW];
                s0_we <= eff_cand_addr[BUCKET_SLOT_WIDTH-1:0];
            end
        end
    end

    localparam [23:0] MAX_VOXEL_NUM = 24'd20;  // 每体素最多 20 点
    localparam integer PT_WIDTH = 16;
    localparam integer POINTS_PER_ROW = BRAM_DATA_WIDTH / (4 * PT_WIDTH);  // 640/64 = 10
    localparam integer EXPEND_VOXEL_ROW = (MAX_VOXEL_NUM + POINTS_PER_ROW - 1) / POINTS_PER_ROW;  // ceil(20/10)=2
    wire [TIMER_WIDTH-1:0] ts_reg = (s1_valid) ? (s1_time - r_ts) : {TIMER_WIDTH{1'b0}};
    wire expired = (r_status == ST_OCCU) && (s1_force_expire || ts_reg >= LIFE_CYCLE);
    assign kill_expired = expired;
    // wire [BRAM_ADDR_WIDTH-1:0] bram_expire_row_addr = (s1_addr * EXPEND_VOXEL_ROW) + (r_pn / POINTS_PER_ROW);
    // assign bram_expire_addr_a = expired ? bram_expire_row_addr : {BRAM_ADDR_WIDTH{1'b0}};

    // -------------------------------------------------------------------------
    // REVISED: BRAM A to BRAM B 搬运 Pipeline & 环形覆盖缓存设计
    // -------------------------------------------------------------------------

    // 1. 小型 Task FIFO：用于缓存连续的 expired 任务，避免 BRAM 读端口冲突
    localparam TASK_WIDTH = ADDR_WIDTH + 2 * COORD_WIDTH + VN_WIDTH;
    reg [TASK_WIDTH-1:0] task_fifo_mem[0:15];  // 16深度通常已足够缓冲峰值
    reg [3:0] task_wr_ptr;
    reg [3:0] task_rd_ptr;
    reg [4:0] task_count;

    wire task_push = expired;
    wire task_pop;  // 由下游 FSM 控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            task_wr_ptr <= 4'd0;
            task_rd_ptr <= 4'd0;
            task_count  <= 5'd0;
        end else begin
            // 写入 FIFO
            if (task_push) begin
                task_fifo_mem[task_wr_ptr] <= {s1_addr, r_key_x, r_key_y, r_pn};
                task_wr_ptr <= task_wr_ptr + 1'b1;
            end
            // 读出 FIFO
            if (task_pop) begin
                task_rd_ptr <= task_rd_ptr + 1'b1;
            end
            // 计数更新
            if (task_push && !task_pop) task_count <= task_count + 1'b1;
            else if (!task_push && task_pop) task_count <= task_count - 1'b1;
            else task_count <= task_count;  // 同时 push/pop 时计数不变
        end
    end

    wire                          task_empty = (task_count == 0);
    wire        [ TASK_WIDTH-1:0] task_dout = task_fifo_mem[task_rd_ptr];

    // 解析 Task FIFO 输出
    wire        [ ADDR_WIDTH-1:0] task_addr = task_dout[TASK_WIDTH-1-:ADDR_WIDTH];
    wire signed [COORD_WIDTH-1:0] task_kx = task_dout[2*COORD_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire signed [COORD_WIDTH-1:0] task_ky = task_dout[COORD_WIDTH+VN_WIDTH-1-:COORD_WIDTH];
    wire        [   VN_WIDTH-1:0] task_pn = task_dout[VN_WIDTH-1-:VN_WIDTH];


    // 2. 读取 BRAM A 与 通知外部 PFE 的 2-cycle FSM
    reg                           copy_st;
    localparam ST_IDLE = 1'b0;
    localparam ST_READ_R1 = 1'b1;

    reg [BRAM_ADDR_WIDTH-1:0] fsm_read_addr;
    reg                       fsm_read_en;
    reg                       task_pop_reg;
    reg [BRAM_ADDR_WIDTH-1:0] bram_b_wr_ptr;  // BRAM B 的环形写指针
    reg [     ADDR_WIDTH-1:0] fsm_task_addr;  // 新增：用于暂存当前任务的基准地址
    reg [BRAM_ADDR_WIDTH-1:0] task_base_ptr;  // PFE_CACHE 里的地址
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            copy_st       <= ST_IDLE;
            fsm_read_en   <= 1'b0;
            fsm_read_addr <= {BRAM_ADDR_WIDTH{1'b0}};
            fifo_in_valid <= 1'b0;
            fifo_in_data  <= {EW{1'b0}};
            task_pop_reg  <= 1'b0;
            fsm_task_addr <= {ADDR_WIDTH{1'b0}};
            task_base_ptr <= {BRAM_ADDR_WIDTH{1'b0}};
        end else begin
            task_pop_reg  <= 1'b0;
            fifo_in_valid <= 1'b0;
            case (copy_st)
                ST_IDLE: begin
                    if (!task_empty && fifo_in_ready) begin
                        copy_st       <= ST_READ_R1;
                        fsm_read_en   <= 1'b1;

                        // 1. 发起第 1 行读取
                        fsm_read_addr <= task_addr * EXPEND_VOXEL_ROW;

                        // 2. 【关键修复】锁存当前地址，因为马上要 pop FIFO 了
                        fsm_task_addr <= task_addr;

                        // 4. 【关键修复】提前拉高 pop_reg
                        // 这样在 ST_READ_R1 周期内 FIFO 就会执行 pop。
                        // 等下个周期回到 IDLE 时，task_empty 已经完美更新。
                        task_pop_reg  <= 1'b1;
                    end else begin
                        fsm_read_en <= 1'b0;
                    end
                end

                ST_READ_R1: begin
                    copy_st       <= ST_IDLE;
                    fsm_read_en   <= 1'b1;

                    // 3. 通知 PFE
                    fifo_in_valid <= 1'b1;
                    fifo_in_data  <= {task_kx, task_ky, task_base_ptr, task_pn};
                    task_base_ptr <= task_base_ptr + EXPEND_VOXEL_ROW[BRAM_ADDR_WIDTH-1:0];
                    // 【关键修复】使用上一拍锁存的 fsm_task_addr，而不是直连 FIFO 的线
                    fsm_read_addr <= (fsm_task_addr * EXPEND_VOXEL_ROW) + 1'b1;
                end
            endcase
        end
    end

    assign task_pop = task_pop_reg;
    assign bram_expire_addr_a = fsm_read_addr;
    assign bram_expire_wr_a = 1'b0;


    // 3. BRAM B 的写控制流水线 (紧跟 BRAM A 的读使能延迟 1 拍)
    reg fsm_read_en_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_read_en_d1       <= 1'b0;
            bram_b_wr_ptr        <= {BRAM_ADDR_WIDTH{1'b0}};
            bram_expire_addr_b   <= {BRAM_ADDR_WIDTH{1'b0}};
            bram_expire_wrdata_b <= {BRAM_DATA_WIDTH{1'b0}};
            bram_expire_bwen_b   <= {(BRAM_DATA_WIDTH / 8) {1'b0}};
        end else begin
            fsm_read_en_d1 <= fsm_read_en;

            // BRAM A 的数据在 read_en 发出后的下一个周期可用
            if (fsm_read_en_d1) begin
                bram_expire_wrdata_b <= bram_expire_rdata_a;
                bram_expire_addr_b   <= bram_b_wr_ptr;
                bram_expire_bwen_b   <= {(BRAM_DATA_WIDTH / 8) {1'b1}};
                bram_expire_wr_b     <= 1'b1;

                // 写指针递增，加满自动归零实现环形覆盖
                bram_b_wr_ptr        <= bram_b_wr_ptr + 1'b1;
            end else begin
                bram_expire_wr_b   <= 1'b0;
                bram_expire_bwen_b <= {(BRAM_DATA_WIDTH / 8) {1'b0}};
            end
        end
    end


    // -------------------------------------------------------------------------
    // Hash Tombstone (墓碑) 写入逻辑，与 BRAM 搬运完全并行，不受阻塞影响
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kill_valid <= 1'b0;
            b_we       <= {BUCKET_SLOT_WIDTH{1'b0}};
            b_addr     <= {BUCKET_AW{1'b0}};
            b_wdata    <= {ENTRY_WIDTH{1'b0}};
        end else begin
            if (s1_valid && expired) begin  // 发现 expired 即刻击杀，写墓碑
                kill_valid <= 1'b1;
                b_we       <= s1_addr[BUCKET_SLOT_WIDTH-1:0];
                b_addr     <= s1_addr[ADDR_WIDTH-1-:BUCKET_AW];
                b_wdata    <= {ST_TOMB, {COORD_WIDTH{1'b0}}, {COORD_WIDTH{1'b0}}, {VN_WIDTH{1'b0}}, {TIMER_WIDTH{1'b0}}};
            end else begin
                kill_valid <= 1'b0;
                b_we       <= {BUCKET_SLOT_WIDTH{1'b0}};
            end
        end
    end


    // =========================================================================
    // 修改：帧末清空状态机 (EOF Flush FSM) - 精确控制 flush_done
    // =========================================================================

    // 检查流水线和缓存是否全部排空：
    // 1. 扫描结束 (flush_cnt == TABLE_SIZE)
    // 2. S0 和 S1 级流水线中没有因 Flush 而强制过期的任务
    // 3. 中间缓存 fifo 已空 (task_empty)
    // 4. BRAM 搬运状态机处于空闲态 (copy_st == ST_IDLE)
    // 5. 最终过期输出 FIFO 中不仅 level 为 0，且 valid 也拉低了（确保完全被下游吃掉）
    wire all_drained = (flush_cnt == TABLE_SIZE) && 
                       (!s0_force_expire && !s1_force_expire) && 
                       task_empty && 
                       (copy_st == ST_IDLE) && 
                       (fifo_out_level == 0 && !fifo_out_valid);
    // 只有在所有阶段都彻底排空时，才发出 flush_done（只持续 1 个 cycle）
    assign flush_done = flushing && all_drained;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flushing  <= 1'b0;
            flush_cnt <= {(ADDR_WIDTH + 1) {1'b0}};
        end else begin
            if (frame_end && !flushing) begin
                flushing  <= 1'b1;  // 收到帧末信号，启动清空
                flush_cnt <= 0;
            end else if (flushing) begin
                if (flush_cnt < TABLE_SIZE) begin
                    if (!hash_stall) begin
                        flush_cnt <= flush_cnt + 1'b1;
                    end
                end else if (all_drained) begin
                    // 扫完地址后停留在 flushing 状态，直到数据通路完全排空
                    flushing <= 1'b0;
                end
            end
        end
    end


endmodule
