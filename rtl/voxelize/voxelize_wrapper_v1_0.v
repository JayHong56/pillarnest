`timescale 1 ns / 1 ps

    module voxelize_wrapper_v1_0 #
    (
        // Users to add parameters here
        // 提取核心算法的位宽等参数到顶层，方便在 Vivado Block Design 中直接配置
        parameter integer AXIS_DATA_WIDTH = 128,
        parameter integer PT_WIDTH        = 16,
        parameter integer OUT_PT_DIM      = 48,
        parameter integer COORD_WIDTH     = 11,
        // User parameters ends
        // Do not modify the parameters beyond this line


        // Parameters of Axi Slave Bus Interface S00_AXI
        parameter integer C_S00_AXI_DATA_WIDTH  = 32,
        parameter integer C_S00_AXI_ADDR_WIDTH  = 5
    )
    (
        // Users to add ports here
        // -----------------------------------------------------------
        // AXI4-Stream Slave (点云数据输入)
        // -----------------------------------------------------------
        input  wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
        input  wire                       s_axis_tvalid,
        output wire                       s_axis_tready,
        input  wire [               15:0] s_axis_tkeep,
        input  wire                       s_axis_tlast,

        // -----------------------------------------------------------
        // AXI4-Stream Master (输出 Voxel 特征)
        // -----------------------------------------------------------
        output wire [1023:0] m_axis_tdata,
        output wire                           m_axis_tvalid,
        output wire [                  127:0] m_axis_tkeep,
        input  wire                           m_axis_tready,
        output wire                           m_axis_tlast,

        // -----------------------------------------------------------
        // 自定义侧边通道
        // -----------------------------------------------------------
        output wire [COORD_WIDTH-1:0] m_axis_voxel_x,
        output wire [COORD_WIDTH-1:0] m_axis_voxel_y,
        output wire                   m_axis_voxel_valid,

        // -----------------------------------------------------------
        // AXI-Stream Command Interface (连接到 DataMover)
        // -----------------------------------------------------------
        output wire        m_axis_cmd_tvalid,
        input  wire        m_axis_cmd_tready,
        output wire [71:0] m_axis_cmd_tdata,
        // User ports ends
        // Do not modify the ports beyond this line


        // Ports of Axi Slave Bus Interface S00_AXI
        input wire  s00_axi_aclk,
        input wire  s00_axi_aresetn,
        input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
        input wire [2 : 0] s00_axi_awprot,
        input wire  s00_axi_awvalid,
        output wire  s00_axi_awready,
        input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
        input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
        input wire  s00_axi_wvalid,
        output wire  s00_axi_wready,
        output wire [1 : 0] s00_axi_bresp,
        output wire  s00_axi_bvalid,
        input wire  s00_axi_bready,
        input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
        input wire [2 : 0] s00_axi_arprot,
        input wire  s00_axi_arvalid,
        output wire  s00_axi_arready,
        output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
        output wire [1 : 0] s00_axi_rresp,
        output wire  s00_axi_rvalid,
        input wire  s00_axi_rready,
        
        // -----------------------------------------------------------
        // 新增：向外引出的写入基地址端口 (供外部 DataMover 等使用)
        // -----------------------------------------------------------
        output wire [31:0] write_base_addr_out  // <--- 增加这个端口
    );
// Instantiation of Axi Bus Interface S00_AXI
    voxelize_wrapper_v1_0_S00_AXI # ( 
        // 传递新增的用户参数
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .PT_WIDTH(PT_WIDTH),
        .OUT_PT_DIM(OUT_PT_DIM),
        .COORD_WIDTH(COORD_WIDTH),

        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) voxelize_wrapper_v1_0_S00_AXI_inst (
        // 映射新增的用户端口
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),

        .m_axis_voxel_x(m_axis_voxel_x),
        .m_axis_voxel_y(m_axis_voxel_y),
        .m_axis_voxel_valid(m_axis_voxel_valid),

        .m_axis_cmd_tvalid(m_axis_cmd_tvalid),
        .m_axis_cmd_tready(m_axis_cmd_tready),
        .m_axis_cmd_tdata(m_axis_cmd_tdata),

        // AXI-Lite 原始接口映射
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready),
        
        // --- 连出新增的配置引脚 ---
        .write_base_addr_out(write_base_addr_out) // <--- 连接内外层
    );

    // Add user logic here

    // User logic ends

    endmodule