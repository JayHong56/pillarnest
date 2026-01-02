`timescale 1ps / 1ps


module voxelize #(
    // parameter integer DATA_WIDTH = 128,
    // parameter integer ADDR_WIDTH = 12,
    parameter integer DRAM_DATA_WIDTH = 128,
    parameter integer DRAM_ADDR_WIDTH = 16,

    parameter integer AXIS_DATA_WIDTH = 128,
    parameter integer AXIS_ADDR_WIDTH = 16,

    parameter integer AXI_LITE_DATA_WIDTH = 128,
    parameter integer AXI_LITE_ADDR_WIDTH = 32,

    parameter integer BRAM_DATA_WIDTH = 128,
    parameter integer BRAM_ADDR_WIDTH = 19
) (
    input wire clk,
    input wire rst_n

);

    reg                            dram_read_en = 1'b1;
    reg                            dram_write_en = 1'b0;
    wire [  DRAM_ADDR_WIDTH - 1:0] dram_write_size = (1 << DRAM_ADDR_WIDTH) - 1;
    wire [(DRAM_DATA_WIDTH - 1):0] dram_read_address;
    wire [(DRAM_DATA_WIDTH - 1):0] dram_data_out;
    dram #(
        .DATA_WIDTH(DRAM_DATA_WIDTH),
        .ADDR_WIDTH(DRAM_ADDR_WIDTH),  // 65536 depth
        .MEM_FILE("E:\\verilog\\pillarnest\\rtl\\pointcloud\\points_bits_128.txt"),
        .MEM_FILE_LENGTH(34752)
    ) voxel_dram (
        .clk(clk),
        .rst_n(rst_n),
        .en(dram_read_en),
        .we(dram_write_en),
        .write_address(),
        .read_address(dram_read_address),
        .data_in(),
        .data_out(dram_data_out)
    );


    wire S_AXIS_DRAM_TLAST;
    wire [127:0] S_AXIS_DRAM_TDATA;
    wire S_AXIS_DRAM_TVALID;
    wire S_AXIS_DRAM_TREADY;
    // axi stream 读fifo
    adapter_bram_2_axi_stream #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .BRAM_DEPTH(AXIS_ADDR_WIDTH),
        .AXIS_STROBE_WIDTH(AXIS_DATA_WIDTH / 8),
        .USE_KEEP(0),
        .USER_DEPTH(1)
    ) dram_fifo (
        .clk  (clk),
        .rst_n(rst_n),

        //Ping Poing FIFO Read Interface
        .i_axis_user(),
        .i_bram_en(dram_read_en),
        .i_bram_size(dram_write_size),
        .o_bram_addr(dram_read_address),
        .i_bram_data(dram_data_out),
        //AXI Stream Output
        .o_axis_user(),
        .i_axis_ready(S_AXIS_DRAM_TREADY),
        .o_axis_data(S_AXIS_DRAM_TDATA),
        .o_axis_last(S_AXIS_DRAM_TLAST),
        .o_axis_valid(S_AXIS_DRAM_TVALID)
    );


    // AXI4-Lite master write channel (to BRAM-mapped slave)
    wire [  AXI_LITE_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire                             m_axi_awvalid;
    wire                             m_axi_awready;
    wire [  AXI_LITE_DATA_WIDTH-1:0] m_axi_wdata;
    wire [AXI_LITE_DATA_WIDTH/8-1:0] m_axi_wstrb;
    wire                             m_axi_wvalid;
    wire                             m_axi_wready;
    wire [                      1:0] m_axi_bresp;
    wire                             m_axi_bvalid;
    wire                             m_axi_bready;


    localparam [15:0] THRESHOLD_CLOSE = 16'h0100;  // 1.00m
    localparam [15:0] THRESHOLD_BOUDARY = 16'h3800;  // 56.00m
    localparam [15:0] THRESHOLD_BOUDARY_Z_LOW = 16'h0500;  // -5m
    localparam [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h0300;  // +3m
    localparam integer PRE_LAT = 1;  // 预处理固定延迟（拍数占位）
    voxel_coor_FSM #(
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .THRESHOLD_CLOSE(THRESHOLD_CLOSE),
        .THRESHOLD_BOUDARY(THRESHOLD_BOUDARY),
        .THRESHOLD_BOUDARY_Z_LOW(THRESHOLD_BOUDARY_Z_LOW),
        .THRESHOLD_BOUDARY_Z_HIGH(THRESHOLD_BOUDARY_Z_HIGH),
        .PRE_LAT(PRE_LAT)
    ) voxel_coordinate_inst (
        .clk(clk),
        .rst_n(rst_n),
        // AXI Stream Slave (Input)
        .S_AXIS_DRAM_TDATA(S_AXIS_DRAM_TDATA),
        .S_AXIS_DRAM_TKEEP(),
        .S_AXIS_DRAM_TLAST(S_AXIS_DRAM_TLAST),
        .S_AXIS_DRAM_TVALID(S_AXIS_DRAM_TVALID),
        .S_AXIS_DRAM_TREADY(S_AXIS_DRAM_TREADY),

        // Master axi-lite side (output)
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bresp  (m_axi_bresp),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready)
    );

    wire [  BRAM_ADDR_WIDTH-1:0] bram_write_address;
    wire [  BRAM_DATA_WIDTH-1:0] bram_write_data;
    wire [BRAM_DATA_WIDTH/8-1:0] bram_porta_we;
    wire  [BRAM_DATA_WIDTH - 1:0] bram_porta_out;
    axi_lite_bram_writer #(
        .AXI_DATA_WIDTH (AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_LITE_ADDR_WIDTH),
        .BRAM_DATA_WIDTH(BRAM_DATA_WIDTH),
        .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH)
    ) axi_lite_bram_writer_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb),
        .s_axi_wvalid(m_axi_wvalid),
        .s_axi_wready(m_axi_wready),
        .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid),
        .s_axi_bready(m_axi_bready),
        .bram_porta_clk(),
        .bram_porta_rst(),
        .bram_porta_addr(bram_write_address),
        .bram_porta_wrdata(bram_write_data),
        .bram_porta_we(bram_porta_we)
    );

    reg bram_en = 1'b1;
    dual_port_bram #(
        .DATA_WIDTH     (BRAM_DATA_WIDTH),
        .ADDR_WIDTH     (BRAM_ADDR_WIDTH),
        .MEM_FILE       ("NOTHING"),
        .MEM_FILE_LENGTH()

    ) voxel_bram (
        .a_clk (clk),
        .a_wr  (bram_en),
        .a_addr(bram_write_address),
        .a_din (bram_write_data),
        .a_dout(bram_porta_out),

        .b_clk (),
        .b_wr  (),
        .b_addr(),
        .b_din (),
        .b_dout()
    );




endmodule
