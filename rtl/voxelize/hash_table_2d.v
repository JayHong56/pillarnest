module hash_table_tombstone #(
    parameter COORD_WIDTH = 16,
    parameter TABLE_SIZE  = 128,
    parameter ADDR_WIDTH  = 7
) (
    input wire clk,
    input wire rst_n,

    input wire                   req_valid,
    input wire                   req_op,     // 0: Read & Clear, 1: Write/Insert
    input wire [COORD_WIDTH-1:0] key_x,
    input wire [COORD_WIDTH-1:0] key_y,

    output reg                  busy,
    output reg                  found,
    output reg [ADDR_WIDTH-1:0] out_idx,
    output reg                  table_full
);

    //----------------------------------------------------------------
    // 1. 状态定义 (2-bit Status)
    //----------------------------------------------------------------
    localparam ST_EMPTY = 2'b00;
    localparam ST_OCCU = 2'b01;
    localparam ST_TOMB = 2'b10;  // 墓碑

    // 存储结构: {Status(2), Key_X, Key_Y}
    localparam ENTRY_WIDTH = 2 + COORD_WIDTH + COORD_WIDTH;

    reg  [ENTRY_WIDTH-1:0] mem        [0:TABLE_SIZE-1];

    // 读出数据分解
    reg  [ENTRY_WIDTH-1:0] r_data_raw;
    wire [            1:0] r_status;
    wire [COORD_WIDTH-1:0] r_key_x;
    wire [COORD_WIDTH-1:0] r_key_y;

    assign {r_status, r_key_x, r_key_y} = r_data_raw;

    //----------------------------------------------------------------
    // 2. 内部寄存器
    //----------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] initial_hash;
    assign initial_hash = (key_x ^ (key_y << 1)) & (TABLE_SIZE - 1);

    reg [ADDR_WIDTH-1:0] curr_addr;
    reg [  ADDR_WIDTH:0] probe_count;

    // 输入锁存
    reg [COORD_WIDTH-1:0] r_in_x, r_in_y;
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

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            busy       <= 0;
            found      <= 0;
            out_idx    <= 0;
            table_full <= 0;
            // 初始化全为 EMPTY
            for (i = 0; i < TABLE_SIZE; i = i + 1) mem[i] <= {ST_EMPTY, {2 * COORD_WIDTH{1'b0}}};
        end else begin
            case (state)
                S_IDLE: begin
                    found      <= 0;
                    table_full <= 0;
                    if (req_valid) begin
                        busy                 <= 1;
                        r_in_x               <= key_x;
                        r_in_y               <= key_y;
                        r_in_op              <= req_op;

                        curr_addr            <= initial_hash;
                        probe_count          <= 0;

                        // 清除墓碑记录
                        seen_tombstone       <= 0;
                        first_tombstone_addr <= 0;

                        state                <= S_READ;
                    end else begin
                        busy <= 0;
                    end
                end

                S_READ: begin
                    r_data_raw <= mem[curr_addr];
                    state      <= S_CHECK;
                end

                S_CHECK: begin
                    case (r_status) 
                        // ----------------------------------------------------
                        // 情况 A: 这是一个空位 (End of Chain)
                        // ----------------------------------------------------
                        ST_EMPTY: begin
                            if (r_in_op == 1) begin
                                // 写入模式：确认 Key 不存在，可以插入
                                if (seen_tombstone) begin
                                    // 优先复用墓碑位置
                                    state <= S_PRE_WRITE;
                                end else begin
                                    // 直接在当前空位写入
                                    state <= S_WRITE;
                                end
                            end else begin
                                // 查找模式：确实没找到
                                found <= 0;
                                busy  <= 0;
                                state <= S_IDLE;
                            end
                        end

                        // ----------------------------------------------------
                        // 情况 B: 这是一个有效数据位
                        // ----------------------------------------------------
                        ST_OCCU: begin
                            if (r_key_x == r_in_x && r_key_y == r_in_y) begin
                                // --- HIT: 找到了 ---
                                out_idx <= curr_addr; 
                                found   <= 1;
                                busy    <= 0;
                                state   <= S_IDLE;

                                // 读取该位置，标记该位置已删除
                                if (r_in_op == 0) begin
                                    mem[curr_addr][ENTRY_WIDTH-1:ENTRY_WIDTH-2] <= ST_TOMB;
                                end
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

                        // ----------------------------------------------------
                        // 情况 C: 这是一个墓碑
                        // ----------------------------------------------------
                        ST_TOMB: begin
                            // 1. 对于读操作：墓碑意味着“这里没东西，但后面可能有”，所以必须继续找。
                            // 2. 对于写操作：我们记录第一个遇到的墓碑位置，以便后续回收。
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
                        end
                    endcase
                end

                // ----------------------------------------------------
                // 插入地址决策逻辑
                // ----------------------------------------------------
                S_PRE_WRITE: begin
                    // 决策：写在哪里？
                    // 优先复用之前记录的墓碑位置
                    curr_addr <= first_tombstone_addr;
                    // 否则，保持 curr_addr 不变（它现在指向当前的 ST_EMPTY）

                    state <= S_WRITE;
                end

                // ----------------------------------------------------
                // 执行写入
                // ----------------------------------------------------
                S_WRITE: begin
                    // 写入 Status=OCCU, Key=X,Y
                    mem[curr_addr] <= {ST_OCCU, r_in_x, r_in_y};

                    out_idx <= curr_addr;
                    found   <= 1;
                    busy    <= 0;
                    state   <= S_IDLE;
                end
            endcase
        end
    end

endmodule
