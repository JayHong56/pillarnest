module pfn_layer #(
    parameter EXPAND_PT_DIM   = 11,
    parameter COORD_WIDTH     = 11,
    parameter OUT_PT_DIM      = 48,
    parameter PT_WIDTH        = 16,         // 输入数据位宽
    parameter MEM_WEIGHT_FILE = "NOTHING",
    parameter MEM_BIAS_FILE   = "NOTHING",
    parameter WEIGHT_WIDTH    = 16,         // 权重位宽 (通常量化为 INT8)
    parameter ACC_WIDTH       = 32          // 累加器位宽
) (
    input wire clk,
    input wire rst_n,
    // 从上一级模块接收单个点的接口
    input wire s_axis_pfe_valid,
    input wire [EXPAND_PT_DIM*PT_WIDTH-1:0] s_axis_pfe_data,  // Q8.8
    input wire s_axis_pfe_last,  // 指示该点是否为当前 Voxel 的最后一个点
    input wire s_axis_pfe_voxel_valid,
    input wire signed [COORD_WIDTH-1:0] s_axis_pfe_voxel_x,
    input wire signed [COORD_WIDTH-1:0] s_axis_pfe_voxel_y,
    output reg m_axis_out_voxel_valid,
    output reg signed [COORD_WIDTH-1:0] m_axis_out_voxel_x,
    output reg signed [COORD_WIDTH-1:0] m_axis_out_voxel_y,


    // 最终池化后的输出
    output reg m_axis_out_valid
    // output reg  [   OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data
    // output wire                              m_axis_out_data_bit  // 仅用于仿真观察输出数据
);
    reg [OUT_PT_DIM*PT_WIDTH-1:0] m_axis_out_data;
    // assign m_axis_out_data_bit = (m_axis_out_data == {OUT_PT_DIM*PT_WIDTH{1'b1}}) ? 1'b1 : 1'b0; // 仅用于仿真观察输出数据

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

    reg signed [  ACC_WIDTH-1:0] mac_res            [0:OUT_PT_DIM-1];
    reg        [   PT_WIDTH-1:0] relu_res           [0:OUT_PT_DIM-1];
    reg signed [   PT_WIDTH-1:0] max_pool_regs      [0:OUT_PT_DIM-1];
    reg                          linear_val;
    reg                          linear_last;

    reg                          linear_voxel_valid;
    reg signed [COORD_WIDTH-1:0] linear_voxel_x;
    reg signed [COORD_WIDTH-1:0] linear_voxel_y;

    integer                      csv_fd;
    integer                      pfe_csv_fd;
    initial begin
        csv_fd = $fopen("pfn_layer_out.csv", "w");
        if (csv_fd != 0) begin
            $fwrite(csv_fd, "time,voxel_x,voxel_y,out_data_hex\n");
        end else begin
            $display("ERROR: failed to open pfn_layer_out.csv");
        end
    end

    integer oc, ic, pfe_i;
    real    pfe_q88_val;
    initial begin
        pfe_csv_fd = $fopen("pfn_layer_pfe_input_dec.csv", "w");
        if (pfe_csv_fd != 0) begin
            $fwrite(pfe_csv_fd, "time,voxel_x,voxel_y");
            for (pfe_i = 0; pfe_i < EXPAND_PT_DIM; pfe_i = pfe_i + 1) begin
                $fwrite(pfe_csv_fd, ",dim%0d", pfe_i);
            end
            $fwrite(pfe_csv_fd, "\n");
        end else begin
            $display("ERROR: failed to open pfn_layer_pfe_input_dec.csv");
        end
    end

    wire signed [63:0] dequant_val = mac_res[oc] * 994;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            linear_val         <= 1'b0;
            linear_last        <= 1'b0;
            linear_voxel_valid <= 1'b0;
            linear_voxel_x     <= {COORD_WIDTH{1'b0}};
            linear_voxel_y     <= {COORD_WIDTH{1'b0}};

            for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                mac_res[oc]       <= 0;
                relu_res[oc]      <= 0;
                max_pool_regs[oc] <= 0;
            end

            m_axis_out_valid       <= 1'b0;
            m_axis_out_data        <= 0;
            m_axis_out_voxel_valid <= 1'b0;
            m_axis_out_voxel_x     <= {COORD_WIDTH{1'b0}};
            m_axis_out_voxel_y     <= {COORD_WIDTH{1'b0}};
        end else begin
            linear_val             <= s_axis_pfe_valid;
            linear_last            <= s_axis_pfe_last;
            linear_voxel_valid     <= s_axis_pfe_voxel_valid;
            linear_voxel_x         <= s_axis_pfe_voxel_x;
            linear_voxel_y         <= s_axis_pfe_voxel_y;

            m_axis_out_valid       <= 1'b0;
            m_axis_out_voxel_valid <= 1'b0;

            if (s_axis_pfe_valid) begin
                for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                    mac_res[oc] = bias_rom[oc];
                    for (ic = 0; ic < EXPAND_PT_DIM; ic = ic + 1) begin
                        mac_res[oc] = mac_res[oc] + $signed(s_axis_pfe_data[ic*PT_WIDTH+:PT_WIDTH]) *
                            $signed(weight_row_rom[oc][ic*WEIGHT_WIDTH+:WEIGHT_WIDTH]);
                    end

                    if (mac_res[oc] < 0) relu_res[oc] <= 0; // ReLU 激活
                    else relu_res[oc] <= dequant_val[PT_WIDTH+20-1 : 20];  // 乘以994后右移20位
                    // else relu_res[oc] <= mac_res[oc][PT_WIDTH+8-1 : 8];
                end
            end

            if (linear_val) begin
                for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                    if (relu_res[oc] > max_pool_regs[oc]) max_pool_regs[oc] <= relu_res[oc];
                end

                if (linear_last) begin
                    m_axis_out_valid       <= 1'b1;
                    m_axis_out_voxel_valid <= linear_voxel_valid;
                    m_axis_out_voxel_x     <= linear_voxel_x;
                    m_axis_out_voxel_y     <= linear_voxel_y;

                    for (oc = 0; oc < OUT_PT_DIM; oc = oc + 1) begin
                        m_axis_out_data[oc*PT_WIDTH +: PT_WIDTH] <=
                        (relu_res[oc] > max_pool_regs[oc]) ? relu_res[oc] : max_pool_regs[oc];
                        max_pool_regs[oc] <= 0;
                    end
                end
            end
        end
    end

    // Simulation log: when pfe_valid is high, split input vector and write each 16-bit dim as Q8.8 decimal float.
    always @(posedge clk) begin
        if (rst_n && s_axis_pfe_valid) begin
            if (pfe_csv_fd != 0) begin
                $fwrite(pfe_csv_fd, "%0t,%0d,%0d", $time, u_pfe.voxel_x_test, u_pfe.voxel_y_test);
                for (pfe_i = 0; pfe_i < EXPAND_PT_DIM; pfe_i = pfe_i + 1) begin
                    pfe_q88_val = $itor($signed(s_axis_pfe_data[pfe_i*PT_WIDTH +: PT_WIDTH])) / 256.0;
                    $fwrite(pfe_csv_fd, ",%0.6f", pfe_q88_val);
                end
                $fwrite(pfe_csv_fd, "\n");
            end
        end
    end

    // Simulation log: write voxel coordinates and output data to CSV when out_valid is asserted.
    always @(posedge clk) begin
        if (rst_n && m_axis_out_valid) begin
            if (csv_fd != 0) begin
                $fwrite(csv_fd, "%0t,%0d,%0d,%0h\n", $time, u_pfe.voxel_x_test, u_pfe.voxel_y_test, m_axis_out_data);
            end
        end
    end

endmodule
