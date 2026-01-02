module voxel_coor_FSM #(
    parameter integer AXI_LITE_DATA_WIDTH = 128,
    parameter integer AXI_LITE_ADDR_WIDTH = 10,

    parameter [15:0] THRESHOLD_CLOSE = 16'h0100,  // 1.00m
    parameter [15:0] THRESHOLD_BOUDARY = 16'h3800,  // 56.00m
    parameter [15:0] THRESHOLD_BOUDARY_Z_LOW = 16'h0500,  // -5m
    parameter [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h0300,  // +3m
    parameter integer PRE_LAT = 1  // 预处理固定延迟（拍数占位）
) (
    input wire clk,
    input wire rst_n,

    // AXI-Stream in (from DRAM FIFO)
    input  wire [127:0] S_AXIS_DRAM_TDATA,
    input  wire [ 15:0] S_AXIS_DRAM_TKEEP,
    input  wire         S_AXIS_DRAM_TLAST,
    input  wire         S_AXIS_DRAM_TVALID,
    output reg          S_AXIS_DRAM_TREADY,

    // AXI4-Lite master write channel (to BRAM-mapped slave)
    output reg  [AXI_LITE_ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg                            m_axi_awvalid,
    input  wire                           m_axi_awready,

    output reg  [  AXI_LITE_DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [AXI_LITE_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                              m_axi_wvalid,
    input  wire                             m_axi_wready,

    input  wire [1:0] m_axi_bresp,
    input  wire       m_axi_bvalid,
    output reg        m_axi_bready
);

    // ------------------------------------------------------------
    // 1) One-point buffer (capture one input beat)
    // ------------------------------------------------------------
    reg  [  127:0] point_raw;
    reg  [   15:0] point_keep;
    reg            point_last;

    // unpack (optional)
    wire [   31:0] point_cloud_x = point_raw[31:0];
    wire [   31:0] point_cloud_y = point_raw[63:32];
    wire [   31:0] point_cloud_z = point_raw[95:64];
    wire [   31:0] point_cloud_i = point_raw[127:96];

    // float to fixed point
    wire [8+8-1:0] pt_x_int16;
    wire [8+8-1:0] pt_y_int16;
    wire [8+8-1:0] pt_z_int16;
    wire [8+8-1:0] pt_intensity_int16;
    float_to_fixed float2fxp_x (
        .float_in(point_cloud_x),
        .true_fixed_value(pt_x_int16[15:0]),
        .fixed_sign()
    );
    float_to_fixed float2fxp_y (
        .float_in(point_cloud_y),
        .true_fixed_value(pt_y_int16[15:0]),
        .fixed_sign()
    );
    float_to_fixed float2fxp_z (
        .float_in(point_cloud_z),
        .true_fixed_value(pt_z_int16[15:0]),
        .fixed_sign()
    );
    float_to_fixed float2fxp_intensity (
        .float_in(point_cloud_intensity),
        .true_fixed_value(pt_intensity_int16[15:0]),
        .fixed_sign()
    );

    // 转为体素坐标
    reg  [11+5-1:0] bourdary = 16'h2D00;
    reg  [5+11-1:0] Reciprocals_x_y = 16'h3555;
    wire [11+5-1:0] fxp_mul_x_out;
    wire [11+5-1:0] fxp_add_x_out;
    fxp_mul #(
        .WIIA (8),
        .WIFA (8),
        .WIIB (5),
        .WIFB (11),
        .WOI  (11),
        .WOF  (5),
        .ROUND(1)
    ) fxp_mul_x (
        .ina(pt_x_int16[15:0]),
        .inb(Reciprocals_x_y),
        .out(fxp_mul_x_out),
        .overflow()
    );
    fxp_add #(
        .WIIA (11),
        .WIFA (5),
        .WIIB (11),
        .WIFB (5),
        .WOI  (11),
        .WOF  (5),
        .ROUND(1)
    ) fxp_add_x (
        .ina(fxp_mul_x_out),
        .inb(bourdary),
        .out(fxp_add_x_out),
        .overflow()
    );
    wire [11+5-1:0] fxp_mul_y_out;
    wire [11+5-1:0] fxp_add_y_out;
    fxp_mul #(
        .WIIA (8),
        .WIFA (8),
        .WIIB (5),
        .WIFB (11),
        .WOI  (11),
        .WOF  (5),
        .ROUND(1)
    ) fxp_mul_y (
        .ina(pt_y_int16[15:0]),
        .inb(Reciprocals_x_y),
        .out(fxp_mul_y_out),
        .overflow()
    );
    fxp_add #(
        .WIIA (11),
        .WIFA (5),
        .WIIB (11),
        .WIFB (5),
        .WOI  (11),
        .WOF  (5),
        .ROUND(1)
    ) fxp_add_y (
        .ina(fxp_mul_y_out),
        .inb(bourdary),
        .out(fxp_add_y_out),
        .overflow()
    );
    // 截断
    wire [10:0] voxel_x = fxp_add_x_out[15:5];
    wire [10:0] voxel_y = fxp_add_y_out[15:5];
    // 取绝对值
    wire [15:0] ABS_pt_x_int16;
    wire [15:0] ABS_pt_y_int16;
    wire [15:0] ABS_pt_z_int16;

    assign ABS_pt_x_int16 = (pt_x_int16[15]) ? (~pt_x_int16 + 1'b1) : pt_x_int16;
    assign ABS_pt_y_int16 = (pt_y_int16[15]) ? (~pt_y_int16 + 1'b1) : pt_y_int16;
    assign ABS_pt_z_int16 = (pt_z_int16[15]) ? (~pt_z_int16 + 1'b1) : pt_z_int16;

    // 这里给一个“边界判断结果”的占位
    // keep_point=1 -> 写 BRAM; keep_point=0 -> 丢弃
    reg keep_point;
    // 边界控制
    always @(*) begin
        if (!rst_n) begin
            keep_point <= 1'b0;
        end else begin
            if ((ABS_pt_x_int16 <= THRESHOLD_CLOSE) && (ABS_pt_y_int16 <= THRESHOLD_CLOSE)) begin
                keep_point <= 1'b0;
            end else if (ABS_pt_x_int16 > THRESHOLD_BOUDARY || ABS_pt_y_int16 > THRESHOLD_BOUDARY) begin
                keep_point <= 1'b0;
            end else if (ABS_pt_z_int16[15] ? (ABS_pt_z_int16 > THRESHOLD_BOUDARY_Z_LOW) : 
                                              (ABS_pt_z_int16 > THRESHOLD_BOUDARY_Z_HIGH)) begin
                keep_point <= 1'b0;
            end else begin
                keep_point <= 1'b1;
            end
        end
    end

    // 体素存BRAM的索引哈希表
    reg hash_req_valid;
    reg hash_req_op;  // 0: read, 1: write
    // outputs
    localparam VOXEL_WIDTH = 10;
    localparam HASH_TABLE_SIZE = 128;
    localparam HASH_ADDR_WIDTH = 7;  // log2(HASH_TABLE_SIZE)=7
    wire hash_found;
    wire hash_busy;
    wire hash_table_full;
    wire [HASH_ADDR_WIDTH-1:0] hash_out_idx;
    hash_table_tombstone #(
        .COORD_WIDTH(VOXEL_WIDTH),
        .TABLE_SIZE (HASH_TABLE_SIZE),
        .ADDR_WIDTH (HASH_ADDR_WIDTH)
    ) u_hash_table_tombstone (
        .clk      (clk),
        .rst_n    (rst_n),
        .req_valid(hash_req_valid),
        .req_op   (hash_req_op),
        .key_x    (voxel_x),
        .key_y    (voxel_y),

        .busy      (hash_busy),
        .found     (hash_found),
        .out_idx   (hash_out_idx),
        .table_full(hash_table_full)
    );


    // ------------------------------------------------------------
    // 2) Your preprocessing blocks (placeholders)
    //    你已有 float_to_fixed / fxp_mul / fxp_add 等模块实例，可放这里
    // ------------------------------------------------------------

    // 这里给一个“处理后点”的占位（你可换成实际输出）
    reg [127:0] point_proc;

    // 例如你想用 abs(x), abs(y) vs threshold，这里只是占位，别当真：
    // keep_point <= (abs_x <= THRESHOLD_CLOSE) && (abs_y <= THRESHOLD_CLOSE);

    // ------------------------------------------------------------
    // 3) AXI-Lite write sequencing (4x 32-bit writes for 128-bit point)
    // ------------------------------------------------------------
    reg aw_done, w_done;  // handshake trackers

    wire [127:0] cur_wdata = point_proc;

    wire [AXI_LITE_ADDR_WIDTH-1:0] cur_awaddr = {
        5'd20 * hash_out_idx, 2'd0
    };  // 20 bytes per entry, 4 words

    // ------------------------------------------------------------
    // 4) FSM (non-pipelined: one point in flight)
    // ------------------------------------------------------------
    localparam ST_IN = 3'd0;
    localparam ST_PREP = 3'd1;
    localparam ST_DROP = 3'd2;
    localparam ST_AW = 3'd3;
    localparam ST_B = 3'd4;

    reg [2:0] state;

    // preprocessing wait counter (for fixed latency PRE_LAT)
    reg [$clog2(PRE_LAT+1)-1:0] pre_cnt;

    // convenience
    wire s_fire = S_AXIS_DRAM_TVALID && S_AXIS_DRAM_TREADY;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IN;

            S_AXIS_DRAM_TREADY <= 1'b1;

            point_raw <= 128'd0;
            point_keep <= 16'd0;
            point_last <= 1'b0;

            point_proc <= 128'd0;
            keep_point <= 1'b0;

            // base_addr <= {AXI_LITE_ADDR_WIDTH{1'b0}};
            // word_idx <= 2'd0;

            m_axi_awaddr <= {AXI_LITE_ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= 32'd0;
            m_axi_wstrb <= {AXI_LITE_DATA_WIDTH / 8{1'b1}};
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;

            aw_done <= 1'b0;
            w_done <= 1'b0;

            pre_cnt <= 'd0;
        end else begin
            // defaults that are safe to override per-state
            // (do not blindly clear valids; we keep them asserted until handshake)
            case (state)
                // ------------------------------------------------------------
                // ST_IN: accept exactly one point from DRAM AXIS
                // ------------------------------------------------------------
                ST_IN: begin
                    S_AXIS_DRAM_TREADY <= 1'b1;
                    // make sure AXI-lite signals are idle
                    m_axi_awvalid      <= 1'b0;
                    m_axi_wvalid       <= 1'b0;
                    m_axi_bready       <= 1'b0;

                    aw_done            <= 1'b0;
                    w_done             <= 1'b0;
                    // word_idx           <= 2'd0;
                    pre_cnt            <= 'd0;
                    hash_req_op        <= 1'b1;  // write
                    hash_req_valid     <= 1'b0;
                    if (s_fire) begin
                        // capture one point
                        point_raw <= S_AXIS_DRAM_TDATA;
                        point_keep <= S_AXIS_DRAM_TKEEP;
                        point_last <= S_AXIS_DRAM_TLAST;

                        // stop upstream until we finish this point
                        S_AXIS_DRAM_TREADY <= 1'b0;

                        // start preprocessing
                        state <= ST_PREP;
                        hash_req_valid <= 1'b1;
                        hash_req_op    <= 1'b1;  // write
                    end
                end

                // ------------------------------------------------------------
                // ST_PREP: wait for preprocessing to finish (fixed latency placeholder)
                // Replace with "if (float2fixed_done && fxp_done ...)" if you have done signals
                // ------------------------------------------------------------
                ST_PREP: begin
                    S_AXIS_DRAM_TREADY <= 1'b0;

                    if (pre_cnt == PRE_LAT - 1) begin
                        pre_cnt    <= 'd0;

                        // ---------------------------
                        // TODO: put your real preprocessing result here
                        // point_proc <= { ... computed ... };
                        // keep_point <= boundary_check_result;
                        // base_addr  <= computed_bram_addr;
                        // ---------------------------
                        point_proc <= point_raw;  // placeholder: passthrough
                        // base_addr  <= base_addr;  // placeholder: keep current

                        // decide drop or write
                        if (keep_point) begin
                            if (hash_found) begin
                                state <= ST_PREP;
                            end else begin
                                state <= ST_AW;
                                hash_req_valid <= 1'b0;
                            end
                        end else state <= ST_DROP;
                    end else begin
                        pre_cnt <= pre_cnt + 1'b1;
                    end
                end

                // ------------------------------------------------------------
                // ST_DROP: drop this point, immediately go back to read next point
                // ------------------------------------------------------------
                ST_DROP: begin
                    // no AXI-lite write
                    state <= ST_IN;
                end

                // ------------------------------------------------------------
                // ST_AW_W: issue AW and W for current 32-bit word (AXI-Lite single write)
                // We keep AWVALID/WVALID asserted until handshake happens.
                // ------------------------------------------------------------
                ST_AW: begin
                    // Drive current write signals
                    m_axi_awaddr <= cur_awaddr;
                    m_axi_wdata  <= cur_wdata;
                    m_axi_wstrb  <= {AXI_LITE_DATA_WIDTH{1'b1}};  // full write

                    // assert valids if not done
                    if (!aw_done) m_axi_awvalid <= 1'b1;
                    if (!w_done) m_axi_wvalid <= 1'b1;

                    // handshake tracking
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_done <= 1'b1;
                    end

                    // once both AW and W are accepted, wait for B
                    if (aw_done && w_done) begin
                        m_axi_bready <= 1'b1;
                        state <= ST_B;
                    end
                end

                // ------------------------------------------------------------
                // ST_B: wait for write response
                // On BVALID, consume it and move to next word or finish point
                // ------------------------------------------------------------
                ST_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        state <= ST_IN;
                        aw_done <= 1'b0;
                        w_done <= 1'b0;
                    end else begin
                        m_axi_bready <= 1'b1;  // keep ready until valid
                        state <= ST_B;
                    end
                end

                default: state <= ST_IN;
            endcase
        end
    end

endmodule
