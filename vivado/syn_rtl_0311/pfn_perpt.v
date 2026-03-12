module pfn_layer #(
    parameter EXPAND_PT_DIM   = 11,
    parameter OUT_PT_DIM      = 48,
    parameter PT_WIDTH        = 16,         // 输入数据位宽
    parameter MEM_WEIGHT_FILE = "NOTHING",
    parameter MEM_BIAS_FILE   = "NOTHING",
    parameter WEIGHT_WIDTH    = 16,         // 权重位宽 (通常量化为 INT8)
    parameter ACC_WIDTH       = 32          // 累加器位宽
) (
    input  wire                              clk,
    input  wire                              rst_n,
    // 从上一级模块接收单个点的接口
    input  wire                              s_axis_pfe_valid,
    input  wire [EXPAND_PT_DIM*PT_WIDTH-1:0] s_axis_pfe_data,
    input  wire                              s_axis_pfe_last,   // 指示该点是否为当前 Voxel 的最后一个点
    // 最终池化后的输出
    output reg                               m_axis_out_valid,
    output reg  [   OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data
);
    // reg [OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data;
    wire m_axis_out_data_bit = m_axis_out_data == {OUT_PT_DIM*PT_WIDTH{1'b1}} ? 1'b1 : 1'b0; // 仅用于仿真观察输出数据

    // 1. 权重与偏置 ROM (或者从 AXI 读取的寄存器)
    // 存放量化后的 Weight_fused, B_fused
    reg signed [EXPAND_PT_DIM*WEIGHT_WIDTH-1:0] weight_row_rom[0:OUT_PT_DIM-1];
    reg signed [ACC_WIDTH-1:0] bias_rom[0:OUT_PT_DIM-1];

    initial begin
        $display("Loading weight from %s", MEM_WEIGHT_FILE);
        $readmemh(MEM_WEIGHT_FILE, weight_row_rom);

        $display("Loading bias from %s", MEM_BIAS_FILE);
        $readmemh(MEM_BIAS_FILE, bias_rom);
    end

    reg signed [ACC_WIDTH-1:0] mac_res      [0:OUT_PT_DIM-1];
    reg        [ PT_WIDTH-1:0] relu_res     [0:OUT_PT_DIM-1];
    reg signed [ PT_WIDTH-1:0] max_pool_regs[0:OUT_PT_DIM-1];
    reg                        linear_val;
    reg                        linear_last;

    integer oc, ic;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            linear_val  <= 1'b0;
            linear_last <= 1'b0;
            for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                mac_res[oc]       <= 0;
                relu_res[oc]      <= 0;
                max_pool_regs[oc] <= 0;
            end
            m_axis_out_valid <= 1'b0;
            m_axis_out_data  <= 0;
        end else begin
            linear_val <= s_axis_pfe_valid;
            linear_last <= s_axis_pfe_last;
            m_axis_out_valid <= 1'b0;

            if (s_axis_pfe_valid) begin
                for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                    mac_res[oc] = bias_rom[oc];
                    for (ic = 0; ic < EXPAND_PT_DIM; ic = ic + 1) begin
                        mac_res[oc] = mac_res[oc] + $signed(s_axis_pfe_data[ic*PT_WIDTH+:PT_WIDTH]) *
                            $signed(weight_row_rom[oc][ic*WEIGHT_WIDTH+:WEIGHT_WIDTH]);
                    end

                    if (mac_res[oc] < 0) relu_res[oc] <= 0;
                    else relu_res[oc] <= mac_res[oc][PT_WIDTH+8-1 : 8];
                end
            end

            if (linear_val) begin
                for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                    if (relu_res[oc] > max_pool_regs[oc]) max_pool_regs[oc] <= relu_res[oc];
                end

                if (linear_last) begin
                    m_axis_out_valid <= 1'b1;
                    for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                        m_axis_out_data[oc*PT_WIDTH +: PT_WIDTH] <=
                            (relu_res[oc] > max_pool_regs[oc]) ? relu_res[oc] : max_pool_regs[oc];
                        max_pool_regs[oc] <= 0;
                    end
                end
            end
        end
    end

endmodule
