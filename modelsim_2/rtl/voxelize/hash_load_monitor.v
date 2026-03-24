module hash_load_monitor #(
    parameter BUCKETS   = 64,
    parameter BUCKET_AW = 6,
    parameter MAX_SLOTS = 4
) (
    input wire clk,
    input wire rst_n,

    input wire                 main_write_en,
    input wire [BUCKET_AW-1:0] main_write_addr,

    input wire s1_valid,
    input wire s1_free_found,

    input wire                 kill_valid,
    input wire [BUCKET_AW-1:0] kill_addr,

    input  wire [BUCKET_AW-1:0] debug_addr,
    output wire [          2:0] debug_load,

    output reg [BUCKET_AW:0] total_full_buckets,
    output reg [        8:0] total_load           // 64*4 = 256, need 9 bits
);

    reg [2:0] bucket_load[0:BUCKETS-1];

    reg prev_op_was_insert;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prev_op_was_insert <= 1'b0;
        else if (s1_valid) begin
            prev_op_was_insert <= s1_free_found;
        end
    end

    integer i, j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_full_buckets <= 0;
            total_load <= 0;
            for (i = 0; i < BUCKETS; i = i + 1) begin
                bucket_load[i] <= 3'd0;
            end
        end else begin
            if (main_write_en && prev_op_was_insert) begin
                if (bucket_load[main_write_addr] < MAX_SLOTS) begin
                    bucket_load[main_write_addr] <= bucket_load[main_write_addr] + 1'b1;

                    if (bucket_load[main_write_addr] == 3'd3) total_full_buckets <= total_full_buckets + 1'b1;
                end
            end else if (!main_write_en && kill_valid) begin
                if (bucket_load[kill_addr] > 3'd0) begin
                    bucket_load[kill_addr] <= bucket_load[kill_addr] - 1'b1;

                    if (bucket_load[kill_addr] == 3'd4) total_full_buckets <= total_full_buckets - 1'b1;
                end
            end

            // Calculate total load of all buckets
            total_load <= 0;
            for (j = 0; j < BUCKETS; j = j + 1) begin
                total_load <= total_load + bucket_load[j];
            end
        end
    end

    assign debug_load = bucket_load[debug_addr];

endmodule
