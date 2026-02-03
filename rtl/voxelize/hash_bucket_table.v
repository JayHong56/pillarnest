module hash_bucket_table #(
    parameter COORD_WIDTH       = 11,
    parameter VN_WIDTH          = 5,        // point number width
    parameter LIFE_CYCLE        = 16'd100,
    parameter TIMER_WIDTH       = 16,
    parameter ADDR_WIDTH        = 8,        // 8 -> 256 depths
    parameter TABLE_SIZE        = 256,
    parameter BUCKETS           = 64,
    parameter BUCKET_SLOT_WIDTH = 2         // 4 slots per bucket
) (
    input wire clk,
    input wire rst_n,

    input  wire                          req_valid,
    output wire                          req_ready,
    input  wire signed [COORD_WIDTH-1:0] key_x,
    input  wire signed [COORD_WIDTH-1:0] key_y,

    output reg                                          busy,
    output reg                                          found,
    output reg  [                       ADDR_WIDTH-1:0] out_idx,               // 0..255 = {bucket[5:0], way[1:0]}
    output reg  [                         VN_WIDTH-1:0] out_point_number,
    output reg                                          table_full,
    // axi-stream 
    output wire                                         m_axis_expire_tvalid,
    input  wire                                         m_axis_expire_tready,
    output wire [2*COORD_WIDTH+ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata    //22+7+5
);

    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;
    localparam BUCKET_AW = $clog2(BUCKETS);
    localparam ENTRY_WIDTH = 2 + COORD_WIDTH + COORD_WIDTH + VN_WIDTH + TIMER_WIDTH;


    reg  [BUCKET_AW-1:0] a_addr;
    wire [BUCKET_AW-1:0] a_addr_shadow;
    reg  [BUCKET_AW-1:0] main_write_addr_bucket;
    reg [ENTRY_WIDTH-1:0] wdata0_b, wdata1_b, wdata2_b, wdata3_b;
    reg we0_b, we1_b, we2_b, we3_b;
    wire [BUCKET_SLOT_WIDTH-1:0] main_write_addr_slot = we0_b ? 2'd0 : we1_b ? 2'd1 : we2_b ? 2'd2 : we3_b ? 2'd3 : 2'd0;
    wire [ENTRY_WIDTH-1:0] rdata0_a, rdata1_a, rdata2_a, rdata3_a;


    wire [BUCKET_SLOT_WIDTH-1:0] shared_write_we;
    wire arb_we0, arb_we1, arb_we2, arb_we3;
    wire arb_write_en;
    assign arb_we0 = arb_write_en ? (shared_write_we == 2'd0) : 1'b0;
    assign arb_we1 = arb_write_en ? (shared_write_we == 2'd1) : 1'b0;
    assign arb_we2 = arb_write_en ? (shared_write_we == 2'd2) : 1'b0;
    assign arb_we3 = arb_write_en ? (shared_write_we == 2'd3) : 1'b0;
    wire [ ADDR_WIDTH-1:0] shared_write_addr;
    wire [  BUCKET_AW-1:0] arb_addr = shared_write_addr[ADDR_WIDTH-1-:BUCKET_AW];
    wire [ENTRY_WIDTH-1:0] shared_write_data;
    wire [ENTRY_WIDTH-1:0] arb_wdata0 = arb_we0 ? shared_write_data : {ENTRY_WIDTH{1'b0}};
    wire [ENTRY_WIDTH-1:0] arb_wdata1 = arb_we1 ? shared_write_data : {ENTRY_WIDTH{1'b0}};
    wire [ENTRY_WIDTH-1:0] arb_wdata2 = arb_we2 ? shared_write_data : {ENTRY_WIDTH{1'b0}};
    wire [ENTRY_WIDTH-1:0] arb_wdata3 = arb_we3 ? shared_write_data : {ENTRY_WIDTH{1'b0}};

    hash_bucket_array #(
        .ENTRY_WIDTH(ENTRY_WIDTH),
        .BUCKETS    (BUCKETS),
        .BUCKET_AW  (BUCKET_AW)
    ) u_hash_bucket_array (
        .clk     (clk),
        // Port A
        .a_addr  (a_addr),
        .we0_a   (),
        .we1_a   (),
        .we2_a   (),
        .we3_a   (),
        .wdata0_a(),
        .wdata1_a(),
        .wdata2_a(),
        .wdata3_a(),
        .rdata0_a(rdata0_a),
        .rdata1_a(rdata1_a),
        .rdata2_a(rdata2_a),
        .rdata3_a(rdata3_a),
        // Port B
        .b_addr  (arb_addr),
        .we0_b   (arb_we0),
        .we1_b   (arb_we1),
        .we2_b   (arb_we2),
        .we3_b   (arb_we3),
        .wdata0_b(arb_wdata0),
        .wdata1_b(arb_wdata1),
        .wdata2_b(arb_wdata2),
        .wdata3_b(arb_wdata3),
        .rdata0_b(),
        .rdata1_b(),
        .rdata2_b(),
        .rdata3_b()
    );

    reg we0_a_shadow, we1_a_shadow, we2_a_shadow, we3_a_shadow;
    wire [ENTRY_WIDTH-1:0] rdata0_a_shadow, rdata1_a_shadow, rdata2_a_shadow, rdata3_a_shadow;
    hash_bucket_array #(
        .ENTRY_WIDTH(ENTRY_WIDTH),
        .BUCKETS    (BUCKETS),
        .BUCKET_AW  (BUCKET_AW)
    ) u_hash_bucket_array_shadow (
        .clk     (clk),
        // Port A
        .a_addr  (a_addr_shadow),
        .we0_a   (),
        .we1_a   (),
        .we2_a   (),
        .we3_a   (),
        .wdata0_a(),
        .wdata1_a(),
        .wdata2_a(),
        .wdata3_a(),
        .rdata0_a(rdata0_a_shadow),
        .rdata1_a(rdata1_a_shadow),
        .rdata2_a(rdata2_a_shadow),
        .rdata3_a(rdata3_a_shadow),
        // Port B
        .b_addr  (arb_addr),
        .we0_b   (arb_we0),
        .we1_b   (arb_we1),
        .we2_b   (arb_we2),
        .we3_b   (arb_we3),
        .wdata0_b(arb_wdata0),
        .wdata1_b(arb_wdata1),
        .wdata2_b(arb_wdata2),
        .wdata3_b(arb_wdata3),
        .rdata0_b(),
        .rdata1_b(),
        .rdata2_b(),
        .rdata3_b()
    );

    // wire [10:0] x_mixed;
    // wire [10:0] y_mixed;
    // assign x_mixed = (key_x << 2) + key_x;
    // assign y_mixed = (key_y << 3) + key_y;
    wire [BUCKET_AW-1:0] bucket_id;
    hash_func_multiplicative #(
        .COORD_WIDTH(COORD_WIDTH),
        .BUCKET_AW  (BUCKET_AW)
    ) u_hash_func_multiplicative (
        .key_x   (key_x),
        .key_y   (key_y),
        .hash_out(bucket_id)
    );


    reg s0_valid;
    reg signed [COORD_WIDTH-1:0] s0_x, s0_y;
    reg [BUCKET_AW-1:0] s0_bucket;
    reg s1_valid;
    reg signed [COORD_WIDTH-1:0] s1_x, s1_y;
    reg [BUCKET_AW-1:0] s1_bucket;
    reg resume_read_s0;

    reg [TIMER_WIDTH-1:0] global_timer;
    wire did_write = we0_b | we1_b | we2_b | we3_b;
    wire [ENTRY_WIDTH-1:0] main_write_data = (we0_b) ? wdata0_b :
                                        (we1_b) ? wdata1_b :
                                        (we2_b) ? wdata2_b :
                                        (we3_b) ? wdata3_b : {ENTRY_WIDTH{1'b0}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) global_timer <= 0;
        else if (did_write) global_timer <= global_timer + 1'b1;
    end

    function [ENTRY_WIDTH-1:0] make_entry;
        input [1:0] st;
        input signed [COORD_WIDTH-1:0] kx;
        input signed [COORD_WIDTH-1:0] ky;
        input [VN_WIDTH-1:0] pn;
        input [TIMER_WIDTH-1:0] ts;
        begin
            make_entry = {st, kx, ky, pn, ts};
        end
    endfunction

    wire [1:0] st[0:3];
    wire signed [COORD_WIDTH-1:0] kx[0:3];
    wire signed [COORD_WIDTH-1:0] ky[0:3];
    wire [VN_WIDTH-1:0] pn[0:3];
    wire [TIMER_WIDTH-1:0] ts[0:3];
    assign {st[0], kx[0], ky[0], pn[0], ts[0]} = rdata0_a;
    assign {st[1], kx[1], ky[1], pn[1], ts[1]} = rdata1_a;
    assign {st[2], kx[2], ky[2], pn[2], ts[2]} = rdata2_a;
    assign {st[3], kx[3], ky[3], pn[3], ts[3]} = rdata3_a;

    // shadow array select signal
    wire [BUCKET_SLOT_WIDTH-1:0] a_we_shadow;
    wire [ENTRY_WIDTH-1:0] a_rdata_shadow = (a_we_shadow == 2'd0) ? rdata0_a_shadow :
                                    (a_we_shadow == 2'd1) ? rdata1_a_shadow :
                                    (a_we_shadow == 2'd2) ? rdata2_a_shadow :
                                    (a_we_shadow == 2'd3) ? rdata3_a_shadow : {ENTRY_WIDTH{1'b0}};

    wire [BUCKET_AW-1:0] kill_addr_bucket;
    wire [BUCKET_SLOT_WIDTH-1:0] kill_we_bucket;
    wire [ENTRY_WIDTH-1:0] kill_wdata;
    wire [ADDR_WIDTH-1:0] kill_addr = {kill_addr_bucket, kill_we_bucket};
    wire kill_valid;
    hash_expire_manager #(
        .COORD_WIDTH      (COORD_WIDTH),
        .VN_WIDTH         (VN_WIDTH),
        .TIMER_WIDTH      (TIMER_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .LIFE_CYCLE       (LIFE_CYCLE),
        .TABLE_SIZE       (TABLE_SIZE),
        .BUCKET_AW        (BUCKET_AW),
        .BUCKET_SLOT_WIDTH(BUCKET_SLOT_WIDTH),
        .ENTRY_WIDTH      (2 + COORD_WIDTH + COORD_WIDTH + VN_WIDTH + TIMER_WIDTH)
    ) u_hash_expire_manager (
        .clk  (clk),
        .rst_n(rst_n),

        .write_commit(did_write),
        .write_addr  (out_idx),      // 0-255
        .time_now    (global_timer),

        .a_addr_shadow (a_addr_shadow),
        .a_we_shadow   (a_we_shadow),
        .a_rdata_shadow(a_rdata_shadow),

        .b_wdata   (kill_wdata),
        .b_addr    (kill_addr_bucket),
        .b_we      (kill_we_bucket),
        .kill_valid(kill_valid),

        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tready(m_axis_expire_tready),
        .m_axis_expire_tdata (m_axis_expire_tdata)
    );

    wire [ADDR_WIDTH-1:0] main_write_addr = {main_write_addr_bucket, main_write_addr_slot};
    wire did_write_expired;
    hash_arbiter_wr #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .ENTRY_WIDTH    (ENTRY_WIDTH),
        .HASH_SLOT_WIDTH(BUCKET_SLOT_WIDTH)
    ) u_arbiter (
        .clk  (clk),
        .rst_n(rst_n),

        .main_write_we  (did_write),        // 来自 Hash 流水线 Stage 4
        .main_write_addr(main_write_addr),  // {bucket, slot}
        .main_write_data(main_write_data),

        .expired_write_valid(kill_valid),  // 来自 Expire Manager
        .expired_write_addr (kill_addr),   // {bucket, slot}

        .arb_we      (shared_write_we),
        .arb_waddr   (shared_write_addr),
        .arb_wdata   (shared_write_data),
        .arb_write_en(arb_write_en),

        .did_write_expired(did_write_expired)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid <= 1'b0;
            a_addr <= 0;
            s1_valid <= 1'b0;
            s1_bucket <= 0;
        end else begin
            s1_valid  <= s0_valid;
            s1_x      <= s0_x;
            s1_y      <= s0_y;
            s1_bucket <= s0_bucket;

            s0_valid  <= req_valid;
            if (req_valid) begin
                // 寄存
                s0_x      <= key_x;
                s0_y      <= key_y;
                s0_bucket <= bucket_id;
                // 请求读取
                a_addr    <= bucket_id;  // issue read to all 4 BRAMs
            end
        end
    end

    integer i;
    reg hit, free_found;
    reg [1:0] hit_way, free_way;  // 0-3
    always @(*) begin
        hit = 1'b0;
        hit_way = 2'd0;
        free_found = 1'b0;
        free_way = 2'd0;

        for (i = 0; i < 4; i = i + 1) begin
            if (!hit && st[i] == ST_OCCU && kx[i] == s1_x && ky[i] == s1_y) begin  // hit
                hit = 1'b1;
                hit_way = i[1:0];
            end

            if (!free_found && ((st[i] == ST_EMPTY || st[i] == ST_TOMB))) begin  // empty or tomb
                free_found = 1'b1;
                free_way   = i[1:0];
            end
        end
    end

    reg [COORD_WIDTH-1:0] debug_key_x, debug_key_y;

    // -------- actions for current s1 (combinational) --------
    wire action_hit;
    wire action_free;
    wire action_probe;
    wire action_full;

    reg probe_active;
    reg [BUCKET_AW-1:0] probe_count;

    // 当正在探测/恢复，或本拍刚发现 bucket 满要开始探测时，不接新请求
    assign req_ready = ~(probe_active || resume_read_s0 || action_probe);

    // -------- actions for current s1 (combinational) --------
    assign action_hit = s1_valid && hit;
    assign action_free = s1_valid && (!hit) && free_found;
    // probe_count：0 表示起始 bucket；每次 bucket 满且不命中就 +1 并 bucket++
    // 当 probe_count == BUCKETS-1 仍然满 => 真的 table_full
    assign action_probe = s1_valid && (!hit) && (!free_found) && (probe_count < (BUCKETS - 1));
    assign action_full = s1_valid && (!hit) && (!free_found) && (probe_count == (BUCKETS - 1));

    wire [BUCKET_AW-1:0] s1_bucket_next = s1_bucket + {{(BUCKET_AW - 1) {1'b0}}, 1'b1};

    integer fp;  // 文件句柄
    initial begin
        // 1. 打开文件 ( "w" 表示覆盖写入, "a" 表示追加 )
        fp = $fopen("ssimulation_result.csv", "w");

        // 2. 写入表头 (可选)
        $fwrite(fp, "Key_X, Key_Y, Bucket_ID\n");
    end

    // -------- unified control: pipeline + probe + writeback --------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // pipeline regs
            s0_valid               <= 1'b0;
            s1_valid               <= 1'b0;
            s0_x                   <= 0;
            s0_y                   <= 0;
            s0_bucket              <= 0;
            s1_x                   <= 0;
            s1_y                   <= 0;
            s1_bucket              <= 0;

            a_addr                 <= 0;

            // probe control
            probe_active           <= 1'b0;
            probe_count            <= 0;
            resume_read_s0         <= 1'b0;

            // write controls / outputs
            we0_b                  <= 1'b0;
            we1_b                  <= 1'b0;
            we2_b                  <= 1'b0;
            we3_b                  <= 1'b0;
            wdata0_b               <= 0;
            wdata1_b               <= 0;
            wdata2_b               <= 0;
            wdata3_b               <= 0;
            main_write_addr_bucket <= 0;

            busy                   <= 1'b0;
            found                  <= 1'b0;
            table_full             <= 1'b0;
            out_idx                <= 0;
            out_point_number       <= 0;

        end else begin
            // defaults
            we0_b <= 1'b0;
            we1_b <= 1'b0;
            we2_b <= 1'b0;
            we3_b <= 1'b0;

            busy <= 1'b0;
            found <= 1'b0;
            table_full <= 1'b0;

            // -------------------------
            // 1) handle current s1 result (writeback / outputs)
            // -------------------------
            if (action_hit) begin
                busy <= 1'b1;
                found <= 1'b1;

                main_write_addr_bucket <= s1_bucket;
                out_idx <= {s1_bucket, hit_way};
                out_point_number <= pn[hit_way] + 1'b1;

                case (hit_way)
                    2'd0: begin
                        we0_b <= 1'b1;
                        wdata0_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[0] + 1'b1, global_timer);
                    end
                    2'd1: begin
                        we1_b <= 1'b1;
                        wdata1_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[1] + 1'b1, global_timer);
                    end
                    2'd2: begin
                        we2_b <= 1'b1;
                        wdata2_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[2] + 1'b1, global_timer);
                    end
                    2'd3: begin
                        we3_b <= 1'b1;
                        wdata3_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[3] + 1'b1, global_timer);
                    end
                endcase

                $fwrite(fp, "%d, %d, %d\n", s1_x, s1_y, {s1_bucket, hit_way});

            end else if (action_free) begin
                busy <= 1'b1;
                found <= 1'b1;

                main_write_addr_bucket <= s1_bucket;
                out_idx <= {s1_bucket, free_way};
                out_point_number <= {{(VN_WIDTH - 1) {1'b0}}, 1'b1};

                case (free_way)
                    2'd0: begin
                        we0_b <= 1'b1;
                        wdata0_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                    end
                    2'd1: begin
                        we1_b <= 1'b1;
                        wdata1_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                    end
                    2'd2: begin
                        we2_b <= 1'b1;
                        wdata2_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                    end
                    2'd3: begin
                        we3_b <= 1'b1;
                        wdata3_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                    end
                endcase

                // 修正：这里原来写成 hit_way 了，应该是 free_way
                $fwrite(fp, "%d, %d, %d\n", s1_x, s1_y, {s1_bucket, free_way});

            end else if (action_full) begin
                busy <= 1'b1;
                table_full <= 1'b1;
            end

            // -------------------------
            // 2) probe state update + finish handling
            // -------------------------
            if (action_probe) begin
                probe_active <= 1'b1;
                probe_count <= probe_count + {{(BUCKET_AW - 1) {1'b0}}, 1'b1};

                // 钉住当前请求，bucket 递增
                s1_bucket <= s1_bucket_next;

                // 发起下一 bucket 读
                a_addr <= s1_bucket_next;

            end else if (action_hit || action_free || action_full) begin
                // 当前 s1 请求结束
                probe_active <= 1'b0;
                probe_count <= 0;

                // s1 本拍结束后清掉（下一拍再决定推进）
                s1_valid <= 1'b0;

                // 如果 s0 里已经有排队的请求，做 1 拍恢复：重新打 s0_bucket 的读地址
                if (s0_valid) begin
                    resume_read_s0 <= 1'b1;
                    a_addr <= s0_bucket;
                end else begin
                    resume_read_s0 <= 1'b0;
                end
            end

            // -------------------------
            // 3) resume read s0 (1-cycle bubble)
            // -------------------------
            if (resume_read_s0) begin
                // 这一拍只用于把 a_addr 打到 s0_bucket
                // 下一拍 resume_read_s0 会被清掉，然后再允许 s0->s1 推进
                resume_read_s0 <= 1'b0;
            end

            // -------------------------
            // 4) pipeline advance (fast path): only when not probing and not resuming
            // -------------------------
            if (!(probe_active || action_probe || resume_read_s0)) begin
                s1_valid  <= s0_valid;
                s1_x      <= s0_x;
                s1_y      <= s0_y;
                s1_bucket <= s0_bucket;

                s0_valid  <= req_valid;
                if (req_valid) begin
                    s0_x      <= key_x;
                    s0_y      <= key_y;
                    s0_bucket <= bucket_id;

                    a_addr    <= bucket_id;
                end

                // 新的 s1 请求开始时，清 probe 计数
                if (s0_valid) begin
                    probe_active <= 1'b0;
                    probe_count  <= 0;
                end
            end
        end
    end

    hash_load_monitor #(
        .BUCKETS  (64),
        .BUCKET_AW(6),
        .MAX_SLOTS(4)
    ) u_hash_load_monitor (
        .clk            (clk),
        .rst_n          (rst_n),
        .main_write_en  (did_write),
        .main_write_addr(main_write_addr_bucket),
        .s1_valid       (s1_valid),
        .s1_free_found  (free_found),

        .kill_valid(did_write_expired),
        .kill_addr (shared_write_addr),

        .debug_addr        (),
        .debug_load        (),
        .total_full_buckets(total_full_buckets)
    );

    always @(posedge clk) begin
        // 3. 设置触发条件：比如每当有一个有效的写操作时记录
        if (did_write) begin
            // %0t: 时间, %d: 十进制, %h: 十六进制
            // 这里的信号名要换成你模块里实际的信号
            $fwrite(fp, "%d, %d, %d\n", debug_key_x, debug_key_y, out_idx);
        end
    end

    reg [31:0] cnt = 0;
    always @(posedge clk) begin
        if (action_probe) begin
            cnt <= cnt + 1;
        end
    end
endmodule
