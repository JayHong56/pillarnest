module hash_bucket_table #(
    parameter COORD_WIDTH       = 11,
    parameter VN_WIDTH          = 5,        // point number width
    parameter LIFE_CYCLE        = 16'd100,
    parameter TIMER_WIDTH       = 16,
    parameter ADDR_WIDTH        = 8,        // 9 -> 512 depths
    parameter BUCKETS           = 64,
    parameter BUCKET_SLOT_WIDTH = 2,         // 4 slots per bucket
    parameter TABLE_SIZE        = BUCKETS*(1'b1 << BUCKET_SLOT_WIDTH) // 256 slots
) (
    input wire clk,
    input wire rst_n,

    input wire                          req_valid,
    input wire signed [COORD_WIDTH-1:0] key_x,
    input wire signed [COORD_WIDTH-1:0] key_y,

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


    reg [BUCKET_AW-1:0] a_addr_0, a_addr_1, a_addr_2, a_addr_3;
    wire [BUCKET_AW-1:0] a_addr_shadow;
    reg [ENTRY_WIDTH-1:0] wdata0_b, wdata1_b, wdata2_b, wdata3_b;
    reg we0_b, we1_b, we2_b, we3_b;
    reg [BUCKET_AW-1:0] main_write_addr_bucket;
    wire [BUCKET_SLOT_WIDTH-1:0] main_write_addr_slot = we0_b ? 2'd0 : we1_b ? 2'd1 : we2_b ? 2'd2 : we3_b ? 2'd3 : 2'd0;
    wire [ENTRY_WIDTH-1:0] rdata0_a, rdata1_a, rdata2_a, rdata3_a;


    wire [BUCKET_SLOT_WIDTH-1:0] shared_write_we;
    wire arb_we0, arb_we1, arb_we2, arb_we3;
    wire shared_write_en;
    assign arb_we0 = shared_write_en ? (shared_write_we == 2'd0) : 1'b0;
    assign arb_we1 = shared_write_en ? (shared_write_we == 2'd1) : 1'b0;
    assign arb_we2 = shared_write_en ? (shared_write_we == 2'd2) : 1'b0;
    assign arb_we3 = shared_write_en ? (shared_write_we == 2'd3) : 1'b0;
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
        .a_addr_0(a_addr_0),
        .a_addr_1(a_addr_1),
        .a_addr_2(a_addr_2),
        .a_addr_3(a_addr_3),
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
    hash_bucket_array_shadow #(
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
    wire [BUCKET_AW-1:0] bucket_idx_0;
    wire [BUCKET_AW-1:0] bucket_idx_1;
    wire [BUCKET_AW-1:0] bucket_idx_2;
    wire [BUCKET_AW-1:0] bucket_idx_3;
    // Hash 0: 原始
    hash_func_multiplicative #(
        .COORD_WIDTH(COORD_WIDTH),
        .BUCKET_AW  (BUCKET_AW),
        .SEED       (0)             // <--- 种子 0
    ) u_hash_func_0 (
        .key_x   (key_x),
        .key_y   (key_y),
        .hash_out(bucket_idx_0)
    );

    // Hash 1: X 取反
    hash_func_multiplicative #(
        .COORD_WIDTH(COORD_WIDTH),
        .BUCKET_AW  (BUCKET_AW),
        .SEED       (1)             // <--- 种子 1
    ) u_hash_func_1 (
        .key_x   (key_x),
        .key_y   (key_y),
        .hash_out(bucket_idx_1)
    );

    // Hash 2: Y 取反
    hash_func_multiplicative #(
        .COORD_WIDTH(COORD_WIDTH),
        .BUCKET_AW  (BUCKET_AW),
        .SEED       (2)             // <--- 种子 2
    ) u_hash_func_2 (
        .key_x   (key_x),
        .key_y   (key_y),
        .hash_out(bucket_idx_2)
    );

    // Hash 3: 异或扰动
    hash_func_multiplicative #(
        .COORD_WIDTH(COORD_WIDTH),
        .BUCKET_AW  (BUCKET_AW),
        .SEED       (3)             // <--- 种子 3
    ) u_hash_func_3 (
        .key_x   (key_x),
        .key_y   (key_y),
        .hash_out(bucket_idx_3)
    );


    reg s0_valid;
    reg signed [COORD_WIDTH-1:0] s0_x, s0_y;
    reg [BUCKET_AW-1:0] s0_bucket_0, s0_bucket_1, s0_bucket_2, s0_bucket_3;
    reg s1_valid;
    reg signed [COORD_WIDTH-1:0] s1_x, s1_y;
    reg [BUCKET_AW-1:0] s1_bucket_0, s1_bucket_1, s1_bucket_2, s1_bucket_3;

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
        .arb_write_en(shared_write_en),

        .did_write_expired(did_write_expired)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid <= 1'b0;
            a_addr_0 <= 0;
            a_addr_1 <= 0;
            a_addr_2 <= 0;
            a_addr_3 <= 0;
            s1_valid <= 1'b0;

            s1_bucket_0 <= 0;
            s1_bucket_1 <= 0;
            s1_bucket_2 <= 0;
            s1_bucket_3 <= 0;
        end else begin
            s1_valid    <= s0_valid;
            s1_x        <= s0_x;
            s1_y        <= s0_y;
            s1_bucket_0 <= s0_bucket_0;
            s1_bucket_1 <= s0_bucket_1;
            s1_bucket_2 <= s0_bucket_2;
            s1_bucket_3 <= s0_bucket_3;

            s0_valid    <= req_valid;
            if (req_valid) begin
                // 寄存
                s0_x        <= key_x;
                s0_y        <= key_y;
                s0_bucket_0 <= bucket_idx_0;
                s0_bucket_1 <= bucket_idx_1;
                s0_bucket_2 <= bucket_idx_2;
                s0_bucket_3 <= bucket_idx_3;
                // 请求读取
                a_addr_0    <= bucket_idx_0;  // issue read to all 4 BRAMs
                a_addr_1    <= bucket_idx_1;
                a_addr_2    <= bucket_idx_2;
                a_addr_3    <= bucket_idx_3;
            end
        end
    end


    integer i;
    reg hit;
    reg [1:0] hit_way;
    reg free_found;
    reg [1:0] free_way;

    reg [1:0] free_way_rr;
    reg free_found_rr;
    reg [1:0] rr_ptr;

    wire [3:0] free_mask = {
        (st[3] == ST_EMPTY || st[3] == ST_TOMB),
        (st[2] == ST_EMPTY || st[2] == ST_TOMB),
        (st[1] == ST_EMPTY || st[1] == ST_TOMB),
        (st[0] == ST_EMPTY || st[0] == ST_TOMB)
    };

    always @(*) begin
        // --------------------
        // 1) 默认值
        // --------------------
        hit     = 1'b0;
        hit_way = 2'd0;

        // --------------------
        // 2) hit 扫描：保持原逻辑
        // --------------------
        for (i = 0; i < 4; i = i + 1) begin
            if (!hit && st[i] == ST_OCCU && kx[i] == s1_x && ky[i] == s1_y) begin
                hit     = 1'b1;
                hit_way = i[1:0];
            end
        end

        // --------------------
        // 3) free 选择：Round-Robin，从 rr_ptr 开始找第一个空
        // --------------------
        free_found_rr = 1'b0;
        free_way_rr   = 2'd0;

        case (rr_ptr)
            2'd0: begin
                if (free_mask[0]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd0;
                end else if (free_mask[1]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd1;
                end else if (free_mask[2]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd2;
                end else if (free_mask[3]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd3;
                end
            end
            2'd1: begin
                if (free_mask[1]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd1;
                end else if (free_mask[2]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd2;
                end else if (free_mask[3]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd3;
                end else if (free_mask[0]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd0;
                end
            end
            2'd2: begin
                if (free_mask[2]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd2;
                end else if (free_mask[3]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd3;
                end else if (free_mask[0]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd0;
                end else if (free_mask[1]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd1;
                end
            end
            2'd3: begin
                if (free_mask[3]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd3;
                end else if (free_mask[0]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd0;
                end else if (free_mask[1]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd1;
                end else if (free_mask[2]) begin
                    free_found_rr = 1'b1;
                    free_way_rr   = 2'd2;
                end
            end
        endcase

        // 输出给后续写回逻辑用
        free_found = free_found_rr;
        free_way   = free_way_rr;
    end

    function [BUCKET_AW-1:0] addr_of_way;
        input [1:0] way;
        begin
            case (way)
                2'd0: addr_of_way = s1_bucket_0;
                2'd1: addr_of_way = s1_bucket_1;
                2'd2: addr_of_way = s1_bucket_2;
                2'd3: addr_of_way = s1_bucket_3;
            endcase
        end
    endfunction

    integer fp;  // 文件句柄
    initial begin
        // 1. 打开文件 ( "w" 表示覆盖写入, "a" 表示追加 )
        fp = $fopen("ssimulation_result.csv", "w");

        // 2. 写入表头 (可选)
        $fwrite(fp, "Key_X, Key_Y, Bucket_ID, Total_Load\n");
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            we0_b <= 0;
            we1_b <= 0;
            we2_b <= 0;
            we3_b <= 0;
            wdata0_b <= 0;
            wdata1_b <= 0;
            wdata2_b <= 0;
            wdata3_b <= 0;
            main_write_addr_bucket <= 0;

            busy <= 0;
            found <= 0;
            table_full <= 0;
            out_idx <= 0;
            out_point_number <= 0;

            rr_ptr <= 2'd0;
        end else begin
            // defaults
            we0_b <= 0;
            we1_b <= 0;
            we2_b <= 0;
            we3_b <= 0;
            busy <= 0;
            found <= 0;
            table_full <= 0;

            if (s1_valid) begin
                busy <= 1'b1;

                if (hit) begin
                    found <= 1'b1;
                    out_idx <= {addr_of_way(hit_way), hit_way};
                    main_write_addr_bucket <= addr_of_way(hit_way);

                    out_point_number <= pn[hit_way] + 1'b1;
                    case (hit_way)
                        2'd0: begin
                            we0_b <= 1;
                            wdata0_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[0] + 1'b1, global_timer);
                        end
                        2'd1: begin
                            we1_b <= 1;
                            wdata1_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[1] + 1'b1, global_timer);
                        end
                        2'd2: begin
                            we2_b <= 1;
                            wdata2_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[2] + 1'b1, global_timer);
                        end
                        2'd3: begin
                            we3_b <= 1;
                            wdata3_b <= make_entry(ST_OCCU, s1_x, s1_y, pn[3] + 1'b1, global_timer);
                        end
                    endcase
                end else if (free_found) begin
                    found <= 1'b1;
                    out_idx <= {addr_of_way(free_way), free_way};
                    main_write_addr_bucket <= addr_of_way(free_way);

                    out_point_number <= {{(VN_WIDTH - 1) {1'b0}}, 1'b1};
                    case (free_way)
                        2'd0: begin
                            we0_b <= 1;
                            wdata0_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                        end
                        2'd1: begin
                            we1_b <= 1;
                            wdata1_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                        end
                        2'd2: begin
                            we2_b <= 1;
                            wdata2_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                        end
                        2'd3: begin
                            we3_b <= 1;
                            wdata3_b <= make_entry(ST_OCCU, s1_x, s1_y, {{(VN_WIDTH - 1) {1'b0}}, 1'b1}, global_timer);
                        end
                    endcase
                    rr_ptr <= rr_ptr + 2'd1;
                end else begin
                    table_full <= 1'b1;
                end
            end
        end
    end

    wire [8:0] total_load;
    hash_load_monitor #(
        .BUCKETS  (BUCKETS),
        .BUCKET_AW(BUCKET_AW),
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
        .total_full_buckets(total_full_buckets),
        .total_load        (total_load)
    );

    always @(posedge clk) begin
        // 3. 设置触发条件：比如每当有一个有效的写操作时记录
        if (did_write) begin
            // %0t: 时间, %d: 十进制, %h: 十六进制
            // 这里的信号名要换成你模块里实际的信号
            $fwrite(fp, "%d, %d, %d, %d\n", s1_x, s1_y, out_idx, total_load);
        end
    end

endmodule
