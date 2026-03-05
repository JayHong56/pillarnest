module hash_arbiter_wr #(
    parameter ADDR_WIDTH      = 8,
    parameter ENTRY_WIDTH     = 45,  // Status + Key + VN + Timer
    parameter HASH_SLOT_WIDTH = 2
) (
    input wire clk,
    input wire rst_n,

    input wire                   main_write_we,    // 主线写使能
    input wire [ ADDR_WIDTH-1:0] main_write_addr,  // 主线写地址
    input wire [ENTRY_WIDTH-1:0] main_write_data,  // 主线写数据

    input wire                  expired_write_valid,  // 发现过期，请求删除
    input wire [ADDR_WIDTH-1:0] expired_write_addr,   // 待删除地址

    output reg [HASH_SLOT_WIDTH-1:0] arb_we,
    output reg [     ADDR_WIDTH-1:0] arb_waddr,
    output reg [    ENTRY_WIDTH-1:0] arb_wdata,
    output reg                       arb_write_en,

    output reg did_write_expired
);
    localparam ST_TOMB = 2'b10;
    wire fifo_in_ready, fifo_out_valid;
    reg fifo_rd_en;
    wire [ADDR_WIDTH-1:0] fifo_dout_addr;

    wire [7:0] cnt;
    hash_expire_fifo_sync #(
        .WIDTH(ADDR_WIDTH),
        .DEPTH(200)
    ) u_kill_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .in_data (expired_write_addr),
        .in_ready(fifo_in_ready),
        .in_valid(expired_write_valid), // 如果满了就暂时丢弃本次扫描(下轮再扫)，保证不阻塞

        .out_data (fifo_dout_addr),
        .out_valid(fifo_out_valid),
        .out_ready(fifo_rd_en),

        .level(cnt)
    );


    always @(*) begin
        arb_we     = {HASH_SLOT_WIDTH{1'b0}};
        arb_waddr  = 0;
        arb_wdata  = 0;
        fifo_rd_en = 1'b0;
        arb_write_en <= 1'b0;

        did_write_expired <= 1'b0;
        if (main_write_we) begin
            arb_we    = main_write_addr[HASH_SLOT_WIDTH-1:0];
            arb_waddr = main_write_addr;
            arb_wdata = main_write_data;
            arb_write_en <= 1'b1;

            if (fifo_out_valid && (fifo_dout_addr == main_write_addr)) begin  // 主pipeline要写的地址正好是过期地址
                fifo_rd_en = 1'b1;
                did_write_expired <= 1'b1;
            end
        end else if (fifo_out_valid) begin
            fifo_rd_en = 1'b1;

            did_write_expired <= 1'b1;
            arb_we    = fifo_dout_addr[HASH_SLOT_WIDTH-1:0];
            arb_waddr = fifo_dout_addr;
            arb_wdata = {ST_TOMB, {(ENTRY_WIDTH-2){1'b0}}};
            arb_write_en <= 1'b1;
        end
    end

endmodule
