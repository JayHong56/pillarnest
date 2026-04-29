`timescale 1 ns / 1 ps

module voxelize_wrapper_v1_0_S00_AXI #
(
    // AXI4LITE 参数
    parameter integer C_S_AXI_DATA_WIDTH    = 32,
    parameter integer C_S_AXI_ADDR_WIDTH    = 5,
    
    // Voxelize 数据位宽参数
    parameter integer AXIS_DATA_WIDTH = 128,
    parameter integer PT_WIDTH = 16,
    parameter integer OUT_PT_DIM = 48,
    parameter integer COORD_WIDTH = 11
)
(
    // -----------------------------------------------------------
    // 新增：引出给外部模块的配置端口
    // -----------------------------------------------------------
    output wire [31:0] write_base_addr_out, // <--- 新增输出

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

    // -----------------------------------------------------------
    // AXI4-Lite Slave 接口
    // -----------------------------------------------------------
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);


    
    
    // AXI4LITE 信号
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_awaddr;
    reg     axi_awready;
    reg     axi_wready;
    reg [1 : 0]     axi_bresp;
    reg     axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_araddr;
    reg     axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0]  axi_rdata;
    reg [1 : 0]     axi_rresp;
    reg     axi_rvalid;

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 2;

    reg [C_S_AXI_DATA_WIDTH-1:0]    slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0]    slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0]    slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0]    slv_reg3;
    reg [C_S_AXI_DATA_WIDTH-1:0]    slv_reg4;
    wire     slv_reg_rden;
    wire     slv_reg_wren;
    reg [C_S_AXI_DATA_WIDTH-1:0]     reg_data_out;
    integer  byte_index;
    reg  aw_en;

    // 分配连线
    assign S_AXI_AWREADY    = axi_awready;
    assign S_AXI_WREADY     = axi_wready;
    assign S_AXI_BRESP      = axi_bresp;
    assign S_AXI_BVALID     = axi_bvalid;
    assign S_AXI_ARREADY    = axi_arready;
    assign S_AXI_RDATA      = axi_rdata;
    assign S_AXI_RRESP      = axi_rresp;
    assign S_AXI_RVALID     = axi_rvalid;

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_awready <= 1'b0;
          aw_en <= 1'b1;
        end else begin    
          if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
              axi_awready <= 1'b1;
              aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                  aw_en <= 1'b1;
                  axi_awready <= 1'b0;
            end else begin
              axi_awready <= 1'b0;
            end
        end 
    end       

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_awaddr <= 0;
        end else begin    
          if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
              axi_awaddr <= S_AXI_AWADDR;
            end
        end 
    end       

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_wready <= 1'b0;
        end else begin    
          if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en ) begin
              axi_wready <= 1'b1;
            end else begin
              axi_wready <= 1'b0;
            end
        end 
    end       

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    // === 生成 Start 脉冲 ===
    // 监听：当向 slv_reg0 的 bit0 写入 1 时，产生一个时钟周期的脉冲
    wire start_pulse = (slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) && S_AXI_WSTRB[0] && S_AXI_WDATA[0]);

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          slv_reg0 <= 0;
          slv_reg1 <= 0;
          slv_reg2 <= 0;
          slv_reg3 <= 0;
          slv_reg4 <= 0;
        end else begin
        // slv_reg0 的 bit0 自动清零，不保持。其他位按需写入。
        if (slv_reg_wren) begin
            case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
              3'h0: begin
                 for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                    if ( S_AXI_WSTRB[byte_index] == 1 )
                      slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
              end
              3'h1:
                for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                  if ( S_AXI_WSTRB[byte_index] == 1 )
                    slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
              3'h2:
                for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                  if ( S_AXI_WSTRB[byte_index] == 1 )
                    slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
              3'h3:
                for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                  if ( S_AXI_WSTRB[byte_index] == 1 )
                    slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
              3'h4:
                for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
                  if ( S_AXI_WSTRB[byte_index] == 1 )
                    slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
              default : ;
            endcase
          end
          // 自动清除 slv_reg0 的 bit0 (触发位)
          slv_reg0[0] <= 1'b0; 
      end
    end    

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_bvalid  <= 0;
          axi_bresp   <= 2'b0;
        end else begin    
          if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
              axi_bvalid <= 1'b1;
              axi_bresp  <= 2'b0; 
            end else begin
              if (S_AXI_BREADY && axi_bvalid) begin
                  axi_bvalid <= 1'b0; 
                end  
            end
        end
    end   

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_arready <= 1'b0;
          axi_araddr  <= 32'b0;
        end else begin    
          if (~axi_arready && S_AXI_ARVALID) begin
              axi_arready <= 1'b1;
              axi_araddr  <= S_AXI_ARADDR;
            end else begin
              axi_arready <= 1'b0;
            end
        end 
    end       

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_rvalid <= 0;
          axi_rresp  <= 0;
        end else begin    
          if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
              axi_rvalid <= 1'b1;
              axi_rresp  <= 2'b0;
            end else if (axi_rvalid && S_AXI_RREADY) begin
              axi_rvalid <= 1'b0;
            end                
        end
    end    

    wire voxelize_idle;
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
    
    
    assign write_base_addr_out = slv_reg3;
    always @(*) begin
          case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
            // 读取 slv_reg0 时，将内部的 idle 状态映射到 Bit 1
            3'h0   : reg_data_out <= {slv_reg0[31:2], voxelize_idle, slv_reg0[0]};
            3'h1   : reg_data_out <= slv_reg1;
            3'h2   : reg_data_out <= slv_reg2;
            3'h3   : reg_data_out <= slv_reg3;
            3'h4   : reg_data_out <= slv_reg4;
            default : reg_data_out <= 0;
          endcase
    end

    always @( posedge S_AXI_ACLK ) begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
          axi_rdata  <= 0;
        end else begin    
          if (slv_reg_rden) begin
              axi_rdata <= reg_data_out;
            end   
        end
    end    

    // =========================================================================
    // 实例化核心的 Voxelize 模块
    // =========================================================================
    voxelize #(
        .AXIS_DATA_WIDTH (AXIS_DATA_WIDTH),
        .PT_WIDTH        (PT_WIDTH),
        .OUT_PT_DIM      (OUT_PT_DIM),
        .COORD_WIDTH     (COORD_WIDTH)
        // 其它参数在 voxelize 内部有默认值
    ) u_voxelize_core (
        .aclk               (S_AXI_ACLK),
        .aresetn            (S_AXI_ARESETN),
        
        // --- 动态配置参数 ---
        // 0x04: 映射为 DDR 读起始地址
        .base_addr_in       (slv_reg1), 
        // 0x08: 映射为总字节数 (取低23位)
        .frame_bytes_in     (slv_reg2[22:0]), 


        // --- AXI-Stream Slave ---
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tkeep       (s_axis_tkeep),
        .s_axis_tlast       (s_axis_tlast),

        // --- AXI-Stream Master ---
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tkeep       (m_axis_tkeep),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tlast       (m_axis_tlast),

        // --- 侧边通道 ---
        .m_axis_voxel_x     (m_axis_voxel_x),
        .m_axis_voxel_y     (m_axis_voxel_y),
        .m_axis_voxel_valid (m_axis_voxel_valid),

        // --- 控制接口 ---
        // start_pulse 是通过写寄存器产生的单周期高电平
        .start_req          (start_pulse),
        // voxelize_idle 接入 AXI 读总线以便软件查询
        .idle               (voxelize_idle),

        // --- DataMover Command ---
        .m_axis_cmd_tvalid  (m_axis_cmd_tvalid),
        .m_axis_cmd_tready  (m_axis_cmd_tready),
        .m_axis_cmd_tdata   (m_axis_cmd_tdata)
    );

endmodule