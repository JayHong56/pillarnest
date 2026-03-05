module hash_table #(
    parameter COORD_WIDTH = 11,
    parameter TABLE_SIZE = 128,
    parameter ADDR_WIDTH = 7,
    parameter MAX_VOXEL_NUM = 5'd20,
    parameter VN_WIDTH = 5,

    parameter LIFE_CYCLE = 16'd100,  // 经过 100 次由于其他写操作导致的时间流逝后过期
    parameter TIMER_WIDTH = 16  // 计时器足够大，防止频繁溢出回绕问题
) (
    input wire clk,
    input wire rst_n,

    input wire                          req_valid,
    input wire                          req_op,     // 0: Read & Clear, 1: Write/Insert
    input wire signed [COORD_WIDTH-1:0] key_x,
    input wire signed [COORD_WIDTH-1:0] key_y,

    output reg                                          busy,
    output reg                                          found,
    output reg  [                       ADDR_WIDTH-1:0] out_idx,               // 0 ~ 127
    output reg  [                         VN_WIDTH-1:0] out_point_number,      // 1~20
    output reg                                          table_full,
    // axi-stream 
    output reg                                          m_axis_expire_tvalid,
    input  wire                                         m_axis_expire_tready,
    output reg  [2*COORD_WIDTH+ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata    //22+7+5
);
    //----------------------------------------------------------------
    // 1. 状态定义 (2-bit Status)
    //----------------------------------------------------------------
    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;  // 墓碑

    // 存储结构: {Status(2), Key_X, Key_Y}
    localparam ENTRY_WIDTH = 2 + COORD_WIDTH + COORD_WIDTH + VN_WIDTH + TIMER_WIDTH;

    reg         [ENTRY_WIDTH-1:0] mem                         [0:TABLE_SIZE-1];

    // 读出数据分解
    reg         [ENTRY_WIDTH-1:0] r_data_raw;
    wire        [            1:0] r_status;
    wire signed [COORD_WIDTH-1:0] r_key_x;
    wire signed [COORD_WIDTH-1:0] r_key_y;
    wire        [   VN_WIDTH-1:0] point_number;
    wire        [TIMER_WIDTH-1:0] r_timestamp;  // *** NEW ***


    assign {r_status, r_key_x, r_key_y, point_number, r_timestamp} = r_data_raw;
    //----------------------------------------------------------------
    // 2. 内部寄存器
    //----------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] initial_hash;
    wire [10:0] x_mixed;
    wire [10:0] y_mixed;
    // x_mixed = x * 5
    assign x_mixed = (key_x << 2) + key_x;
    // y_mixed = y * 9
    assign y_mixed = (key_y << 3) + key_y;
    // 混合后取低 7 位，同时把高位异或回来以防万一
    assign initial_hash = (x_mixed[6:0] ^ x_mixed[10:7] ^ y_mixed[6:0] ^ y_mixed[10:7]);

    reg [ADDR_WIDTH-1:0] curr_addr;
    reg [  ADDR_WIDTH:0] probe_count;

    // 输入锁存
    reg signed [COORD_WIDTH-1:0] r_in_x, r_in_y;
    reg                      r_in_op;

    // *** 墓碑回收机制专用寄存器 ***
    reg                      seen_tombstone;  // 是否在探测路径上遇到了墓碑
    reg     [ADDR_WIDTH-1:0] first_tombstone_addr;  // 记录遇到的第一个墓碑地址

    integer                  i;
    //----------------------------------------------------------------
    // 3. 状态机
    //----------------------------------------------------------------
    localparam S_IDLE = 0;
    localparam S_READ = 1;
    localparam S_CHECK = 2;
    localparam S_PRE_WRITE = 3;  // 准备写入（可能需要切换地址）
    localparam S_WRITE = 4;
    localparam S_EXPIRE_WAIT = 5;  // *** NEW: 等待数据发送 ***

    reg  [            2:0] state;
    reg  [TIMER_WIDTH-1:0] global_timer;
    wire                   is_expired;
    assign is_expired = (r_status == ST_OCCU) && ((global_timer - r_timestamp) > LIFE_CYCLE);



    reg temp_axis_expire_tready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                   <= S_IDLE;
            busy                    <= 0;
            temp_axis_expire_tready <= 0;
            found                   <= 0;
            out_idx                 <= 0;
            out_point_number        <= 0;
            table_full              <= 0;
            global_timer            <= 0;
            // 初始化全为 EMPTY
            for (i = 0; i < TABLE_SIZE; i = i + 1) mem[i] <= {ST_EMPTY, {(ENTRY_WIDTH - 2) {1'b0}}};
        end else begin
            case (state)
                S_IDLE: begin  // NOTE : 这里out信号不复位，留给外部读bram使用
                    found                <= 0;
                    busy                 <= 0;
                    table_full           <= 0;
                    m_axis_expire_tvalid <= 0;
                    if (req_valid && !found) begin
                        busy                    <= 1;
                        temp_axis_expire_tready <= 0;
                        r_in_x                  <= key_x;
                        r_in_y                  <= key_y;
                        r_in_op                 <= req_op;
                        curr_addr               <= initial_hash;
                        probe_count             <= 0;

                        // 清除墓碑记录
                        seen_tombstone          <= 0;
                        first_tombstone_addr    <= 0;
                        state                   <= S_READ;
                    end else begin
                        busy <= 0;
                    end
                end

                S_READ: begin
                    r_data_raw <= mem[curr_addr];
                    state      <= S_CHECK;
                end

                S_CHECK: begin
                    if (is_expired) begin
                        // 准备发送数据
                        m_axis_expire_tvalid <= 1'b1;
                        m_axis_expire_tdata <= {r_key_x, r_key_y, curr_addr, point_number};

                        // 转入等待状态，阻塞流水线直到发送成功
                        state <= S_EXPIRE_WAIT;
                        temp_axis_expire_tready <= 1'b1;
                    end else if (r_status == ST_TOMB) begin
                        if (r_in_op == 1 && !seen_tombstone) begin
                            seen_tombstone       <= 1;
                            first_tombstone_addr <= curr_addr;
                        end

                        // 继续探测 (Next Probe)
                        probe_count <= probe_count + 1;
                        curr_addr   <= curr_addr + 1;

                        if (probe_count >= TABLE_SIZE) begin
                            // 极端情况：表全是墓碑或占位，没空位了
                            if (r_in_op == 1 && seen_tombstone) begin
                                state <= S_PRE_WRITE;  // 去填第一个遇到的墓碑
                            end else begin
                                table_full <= 1;
                                busy       <= 0;
                                state      <= S_IDLE;
                            end
                        end else begin
                            state <= S_READ;
                        end
                    end else if (r_status == ST_EMPTY) begin
                        if (r_in_op == 1) begin  // 插入模式
                            if (seen_tombstone) state <= S_PRE_WRITE;
                            else state <= S_WRITE;
                        end else begin  // 查找模式
                            found <= 0;
                            busy  <= 0;
                            state <= S_IDLE;
                        end
                    end else begin  // 【ST_OCCU】
                        if (r_key_x == r_in_x && r_key_y == r_in_y) begin
                            // --- HIT: 找到了 ---
                            out_idx <= curr_addr;
                            out_point_number <= point_number + 1'b1;
                            mem[curr_addr] <= {ST_OCCU, r_in_x, r_in_y, (point_number + 1'b1), global_timer};
                            found <= 1;
                            busy <= 0;
                            state <= S_IDLE;

                            // 读取该位置，标记该位置已删除
                            if (r_in_op == 0) begin
                                mem[curr_addr][ENTRY_WIDTH-1:ENTRY_WIDTH-2] <= ST_TOMB;
                            end
                            global_timer <= global_timer + 1;

                        end else begin
                            // --- MISS: 冲突，继续探测 ---
                            probe_count <= probe_count + 1;
                            curr_addr   <= curr_addr + 1;

                            if (probe_count >= TABLE_SIZE) begin
                                // 表全遍历完了都没找到
                                if (r_in_op == 1 && seen_tombstone) begin
                                    // 虽然没空位，但有墓碑，去填墓碑
                                    state <= S_PRE_WRITE;
                                end else begin
                                    table_full <= 1;
                                    busy       <= 0;
                                    state      <= S_IDLE;
                                end
                            end else begin
                                state <= S_READ;
                            end
                        end
                    end
                end

                S_EXPIRE_WAIT: begin  // 阻塞发送过期数据，等待握手完成
                    temp_axis_expire_tready <= 1'b0;

                    if (temp_axis_expire_tready) begin
                        // 握手完成
                        m_axis_expire_tvalid <= 0;  // 拉低Valid

                        // 关键逻辑分支：过期后的位置如何处理？

                        if (r_in_op == 1) begin
                            // 情况A: 当前任务是写入 (Write/Insert)
                            // 既然这个位置过期了，我们刚刚把它发走了，现在它是空的。
                            // 我们可以 *直接征用* 这个位置写入新数据！无需再去找墓碑了。
                            // 这样效率极高，相当于原地替换。

                            mem[curr_addr] <= {ST_OCCU, r_in_x, r_in_y, {(VN_WIDTH - 1) {1'b0}}, 1'b1, global_timer};
                            out_idx <= curr_addr;
                            out_point_number <= 1'b1;
                            found <= 1;
                            busy <= 0;
                            global_timer <= global_timer + 1;  // 写入操作增加计时
                            state <= S_IDLE;
                        end else begin  // r_in_op == 0
                            // 情况B: 当前任务是读取 (Read)
                            // 我们只是路过发现了垃圾，现在清理完了。
                            // 将其标记为墓碑，以便保持探测链不断裂。
                            mem[curr_addr][ENTRY_WIDTH-1:ENTRY_WIDTH-2] <= ST_TOMB;

                            // 记录墓碑（如果需要）
                            if (!seen_tombstone) begin  // 读取模式下其实不需要记录，但为了逻辑统一可保留
                                seen_tombstone <= 1;  // 其实Read模式不写数据，这里不重要
                                // first_tombstone_addr <= curr_addr; 
                            end

                            // 继续探测下一个位置 (这是重点，不能停，因为我们要找的目标可能在后面)
                            probe_count <= probe_count + 1;
                            curr_addr   <= curr_addr + 1;

                            if (probe_count >= TABLE_SIZE) begin
                                table_full <= 1;
                                busy       <= 0;
                                state      <= S_IDLE;
                            end else begin
                                state <= S_READ;
                            end
                        end
                    end
                    // 否则：保持 state = S_EXPIRE_WAIT, m_axis_expire_tvalid = 1，直到 ready 变高
                end

                S_PRE_WRITE: begin
                    curr_addr <= first_tombstone_addr;
                    state <= S_WRITE;
                end

                S_WRITE: begin
                    mem[curr_addr] <= {ST_OCCU, r_in_x, r_in_y, {(VN_WIDTH - 1) {1'b0}}, 1'b1, global_timer};

                    out_idx <= curr_addr;
                    out_point_number <= 1'b1;
                    found <= 1;
                    busy <= 0;
                    global_timer <= global_timer + 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
