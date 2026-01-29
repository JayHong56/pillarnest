module hash_expire_manager #(
    parameter COORD_WIDTH       = 11,
    parameter VN_WIDTH          = 5,
    parameter TIMER_WIDTH       = 16,
    parameter ADDR_WIDTH        = 8,                                                      // 8 -> 256 slots
    parameter LIFE_CYCLE        = 16'd100,
    parameter TABLE_SIZE        = 256,
    parameter BUCKET_AW         = 6,
    parameter BUCKET_SLOT_WIDTH = 2,                                                      // 4 slots per bucket
    parameter ENTRY_WIDTH       = 2 + COORD_WIDTH + COORD_WIDTH + VN_WIDTH + TIMER_WIDTH
) (
    input wire clk,
    input wire rst_n,

    input wire                   write_commit,  // 1-cycle pulse when main path commits a write/update
    input wire [ ADDR_WIDTH-1:0] write_addr,    // the slot address that was written
    input wire [TIMER_WIDTH-1:0] time_now,      // current global_timer value (consistent usage)

    output reg  [        BUCKET_AW-1:0] a_addr_shadow,
    output reg  [BUCKET_SLOT_WIDTH-1:0] a_we_shadow,
    input  wire [      ENTRY_WIDTH-1:0] a_rdata_shadow,

    output reg [      ENTRY_WIDTH-1:0] b_wdata,
    output reg [        BUCKET_AW-1:0] b_addr,
    output reg [BUCKET_SLOT_WIDTH-1:0] b_we,

    // ---- AXI-stream out (expired events) ----
    output wire                                         m_axis_expire_tvalid,
    input  wire                                         m_axis_expire_tready,
    output wire [2*COORD_WIDTH+ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata
);
    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;

    localparam integer EW = 2 * COORD_WIDTH + ADDR_WIDTH + VN_WIDTH;
    wire          fifo_in_ready;
    reg           fifo_in_valid;
    reg  [EW-1:0] fifo_in_data;
    wire          fifo_out_valid;
    wire [EW-1:0] fifo_out_data;
    hash_expire_fifo_sync #(
        .WIDTH(EW),
        .DEPTH(16)
    ) u_hash_expire_fifo_sync (
        .clk  (clk),
        .rst_n(rst_n),

        .in_valid(fifo_in_valid),
        .in_ready(fifo_in_ready),
        .in_data (fifo_in_data),

        .out_valid(fifo_out_valid),
        .out_ready(1'b1),
        .out_data (fifo_out_data),

        .level()
    );
    assign m_axis_expire_tvalid = fifo_out_valid;
    assign m_axis_expire_tdata  = fifo_out_data;


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
            cand_valid <= 1'b0;
            if (write_commit) begin
                dq_mem[dq_wr_ptr] <= write_addr;
                dq_wr_ptr <= (dq_wr_ptr == DQ_DEPTH - 1) ? {($clog2(DQ_DEPTH)) {1'b0}} : (dq_wr_ptr + 1'b1);

                if (dq_count == DQ_DEPTH) begin  // 待在dq中的周期数为DQ_DEPTH，将对其处理（判断过期）
                    cand_addr  <= dq_mem[dq_rd_ptr];
                    cand_valid <= 1'b1;
                    dq_rd_ptr  <= (dq_rd_ptr == DQ_DEPTH - 1) ? {($clog2(DQ_DEPTH)) {1'b0}} : (dq_rd_ptr + 1'b1);
                end else begin
                    dq_count <= dq_count + 1'b1;  // 每次commit自加1
                end
            end
        end
    end

    reg                           s0_valid;
    reg         [ ADDR_WIDTH-1:0] s0_addr;
    reg         [TIMER_WIDTH-1:0] s0_time;
    reg                           s1_valid;
    reg         [ ADDR_WIDTH-1:0] s1_addr;
    reg         [TIMER_WIDTH-1:0] s1_time;

    wire        [            1:0] r_status;
    wire signed [COORD_WIDTH-1:0] r_key_x;
    wire signed [COORD_WIDTH-1:0] r_key_y;
    wire        [   VN_WIDTH-1:0] r_pn;
    wire        [TIMER_WIDTH-1:0] r_ts;

    assign {r_status, r_key_x, r_key_y, r_pn, r_ts} = a_rdata_shadow;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_addr_shadow <= {BUCKET_AW{1'b0}};
            a_we_shadow   <= {BUCKET_SLOT_WIDTH{1'b0}};
            b_wdata       <= {ENTRY_WIDTH{1'b0}};
            s0_valid      <= 1'b0;
            s0_addr       <= {ADDR_WIDTH{1'b0}};
            s0_time       <= {TIMER_WIDTH{1'b0}};
            s1_valid      <= 1'b0;
            s1_addr       <= {ADDR_WIDTH{1'b0}};
            s1_time       <= {TIMER_WIDTH{1'b0}};
        end else begin
            a_we_shadow <= {BUCKET_SLOT_WIDTH{1'b0}};
            s1_valid <= s0_valid;
            s1_addr <= s0_addr;
            s1_time <= s0_time;

            s0_valid <= cand_valid;
            s0_addr <= cand_addr;
            s0_time <= time_now;

            if (cand_valid) begin
                a_addr_shadow <= cand_addr[ADDR_WIDTH-1-:BUCKET_AW];
                a_we_shadow   <= cand_addr[BUCKET_SLOT_WIDTH-1:0];
            end
        end
    end

    wire expired = (r_status == ST_OCCU) && ((s1_time - r_ts) > LIFE_CYCLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

        end else begin
            fifo_in_valid <= 1'b0;
            if (s1_valid && expired) begin  // 确定expired，将数据送入fifo，给出墓碑
                if (fifo_in_ready) begin
                    fifo_in_valid <= 1'b1;  // Push
                    fifo_in_data  <= {r_key_x, r_key_y, s1_addr, r_pn};
                end

                b_we <= s1_addr[BUCKET_SLOT_WIDTH-1:0];
                b_addr <= s1_addr[ADDR_WIDTH-1-:BUCKET_AW];
                b_wdata <= {ST_TOMB, {COORD_WIDTH{1'b0}}, {COORD_WIDTH{1'b0}}, {VN_WIDTH{1'b0}}, {TIMER_WIDTH{1'b0}}};
            end else begin 
                b_we <= {BUCKET_SLOT_WIDTH{1'b0}};
            end
        end
    end
endmodule
