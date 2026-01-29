module hash_func_multiplicative #(
    parameter COORD_WIDTH = 11,
    parameter BUCKET_AW   = 6  // 变更：6 bits -> 64 Buckets
)(
    input  wire signed [COORD_WIDTH-1:0] key_x,
    input  wire signed [COORD_WIDTH-1:0] key_y,
    output wire        [BUCKET_AW-1:0]   hash_out
);

    // 24-bit 素数 (保持不变，适合 DSP48)
    localparam signed [24:0] PRIME_X = 25'd10368889; 
    localparam signed [24:0] PRIME_Y = 25'd10000169; 

    // 乘法结果
    wire signed [35:0] mult_x;
    wire signed [35:0] mult_y;

    assign mult_x = key_x * PRIME_X;
    assign mult_y = key_y * PRIME_Y;

    // 混合
    wire [35:0] mixed = mult_x ^ mult_y;
    
    // 提取哈希值：
    // 我们需要 6 bits。
    // 依然建议取"中间偏高"的位，避开低位的规律性。
    // 之前是 mixed[19:12] (8位)，现在改为 mixed[19:14] (6位)
    assign hash_out = mixed[24 -: BUCKET_AW]; 

endmodule