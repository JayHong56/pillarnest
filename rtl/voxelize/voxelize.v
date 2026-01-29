`timescale 1ps / 1ps

module voxelize #(
    parameter integer DRAM_DATA_WIDTH = 128,
    parameter integer DRAM_ADDR_WIDTH = 16,
    parameter integer AXIS_DATA_WIDTH = 128,
    parameter integer AXIS_ADDR_WIDTH = 16,
    parameter integer BRAM_DATA_WIDTH = 256,  // 64bit * 4points
    parameter integer BRAM_ADDR_WIDTH = 10    // 128pillar * 5brams
) (
    input wire clk,
    input wire rst_n
);
    reg                            dram_read_en = 1'b1;
    reg                            dram_write_en = 1'b0;
    wire [  DRAM_ADDR_WIDTH - 1:0] dram_write_size = (1 << DRAM_ADDR_WIDTH) - 1;
    wire [(DRAM_ADDR_WIDTH - 1):0] dram_read_address;
    wire [(DRAM_DATA_WIDTH - 1):0] dram_data_out;
    dram #(
        .DATA_WIDTH     (DRAM_DATA_WIDTH),
        .ADDR_WIDTH     (DRAM_ADDR_WIDTH),                                                   // 65536 depth
        .MEM_FILE       ("E:\\verilog\\pillarnest\\rtl\\.pointcloud\\points_bits_128.txt"),
        .MEM_FILE_LENGTH(34752)
    ) pointcloud_dram (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (dram_read_en),
        .we           (dram_write_en),
        .write_address(),
        .read_address (dram_read_address),
        .data_in      (),
        .data_out     (dram_data_out)
    );


    wire S_AXIS_DRAM_TLAST;
    wire [AXIS_DATA_WIDTH-1:0] S_AXIS_DRAM_TDATA;
    wire S_AXIS_DRAM_TVALID;
    wire S_AXIS_DRAM_TREADY;
    // axi stream 读fifo
    fifo_ram_2_axi_stream #(
        .AXIS_DATA_WIDTH  (AXIS_DATA_WIDTH),
        .BRAM_DEPTH       (AXIS_ADDR_WIDTH),
        .AXIS_STROBE_WIDTH(AXIS_DATA_WIDTH / 8),
        .USE_KEEP         (0),
        .USER_DEPTH       (1)
    ) fifo_DRAM_2_axi_stream (
        .clk  (clk),
        .rst_n(rst_n),
        //Ping Poing FIFO Read Interface
        .i_axis_user (),
        .i_bram_en   (dram_read_en),
        .i_bram_size (dram_write_size),
        .o_bram_addr (dram_read_address),
        .i_bram_data (dram_data_out),
        //AXI Stream Output
        .o_axis_user (),
        .i_axis_ready(S_AXIS_DRAM_TREADY),
        .o_axis_data (S_AXIS_DRAM_TDATA),
        .o_axis_last (S_AXIS_DRAM_TLAST),
        .o_axis_valid(S_AXIS_DRAM_TVALID)
    );


    localparam COORD_WIDTH = 11;
    localparam PT_WIDTH = 16;
    localparam VN_WIDTH = 5;
    localparam ENPAND_PT_DIM = 11;  // x,y,z,intensity,0,(x-mean,y-mean,z-mean,intensity-mean),(x-vmean,y-vmean,z-vmean,intensity-vmean)
    localparam MAX_VOXEL_NUM = 12'd20;

    localparam HASH_TABLE_SIZE = 256;
    localparam HASH_ADDR_WIDTH = $clog2(HASH_TABLE_SIZE);  // log2(HASH_TABLE_SIZE)
    localparam [15:0] THRESHOLD_CLOSE = 16'h0100;  // 1.00m
    localparam [15:0] THRESHOLD_BOUDARY = 16'h3600;  // 54.00m
    localparam [15:0] THRESHOLD_BOUDARY_Z_LOW = 16'h0500;  // -5m
    localparam [15:0] THRESHOLD_BOUDARY_Z_HIGH = 16'h0300;  // +3m
    localparam integer PRE_LAT = 0;  // 预处理固定延迟（拍数占位）
    localparam [15:0] LIFE_CYCLE = 16'd100;
    wire                                              bram_clk_a;
    wire                                              bram_rst_a;
    wire                                              bram_wr_a;
    wire [                     BRAM_DATA_WIDTH/8-1:0] bram_bwen_a;  // 32-bit Byte Enable
    wire [                       BRAM_ADDR_WIDTH-1:0] bram_addr_a;  // 10-bit Address
    wire [                       BRAM_DATA_WIDTH-1:0] bram_wrdata_a;  // 256-bit Data
    wire                                              m_axis_expire_tvalid;
    wire                                              m_axis_expire_tready;
    wire [2*COORD_WIDTH+HASH_ADDR_WIDTH+VN_WIDTH-1:0] m_axis_expire_tdata;  // NOTE
    voxel_coor_pipe #(
        .AXIS_DATA_WIDTH         (AXIS_DATA_WIDTH),
        .AXIS_ADDR_WIDTH         (AXIS_ADDR_WIDTH),
        .BRAM_DATA_WIDTH         (BRAM_DATA_WIDTH),
        .BRAM_ADDR_WIDTH         (BRAM_ADDR_WIDTH),
        .HASH_TABLE_SIZE         (HASH_TABLE_SIZE),
        .HASH_ADDR_WIDTH         (HASH_ADDR_WIDTH),
        .THRESHOLD_CLOSE         (THRESHOLD_CLOSE),
        .THRESHOLD_BOUDARY       (THRESHOLD_BOUDARY),
        .THRESHOLD_BOUDARY_Z_LOW (THRESHOLD_BOUDARY_Z_LOW),
        .THRESHOLD_BOUDARY_Z_HIGH(THRESHOLD_BOUDARY_Z_HIGH),
        .PRE_LAT                 (PRE_LAT),
        .LIFE_CYCLE              (LIFE_CYCLE)
    ) voxel_coordinate_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        // AXI Stream Slave (Input)
        .S_AXIS_DRAM_TDATA (S_AXIS_DRAM_TDATA),
        .S_AXIS_DRAM_TKEEP (),
        .S_AXIS_DRAM_TLAST (S_AXIS_DRAM_TLAST),
        .S_AXIS_DRAM_TVALID(S_AXIS_DRAM_TVALID),
        .S_AXIS_DRAM_TREADY(S_AXIS_DRAM_TREADY),

        .bram_clk            (bram_clk_a),
        .bram_rst            (),
        .bram_wr             (bram_wr_a),
        .bram_bwen           (bram_bwen_a),
        .bram_addr           (bram_addr_a),
        .bram_wrdata         (bram_wrdata_a),
        .m_axis_expire_tdata (m_axis_expire_tdata),
        .m_axis_expire_tvalid(m_axis_expire_tvalid),
        .m_axis_expire_tready(m_axis_expire_tready)
    );

    wire bram_clk_b;
    wire bram_rst_b;
    wire [BRAM_ADDR_WIDTH-1:0] bram_addr_b;
    wire bram_en_b;
    wire [BRAM_DATA_WIDTH-1:0] bram_rdata_b;
    pfn #(
        .COORD_WIDTH    (COORD_WIDTH),
        .PT_WIDTH       (PT_WIDTH),
        .HASH_ADDR_WIDTH(HASH_ADDR_WIDTH),
        .MAX_VOXEL_NUM  (MAX_VOXEL_NUM),
        .VN_WIDTH       (VN_WIDTH),
        .ENPAND_PT_DIM  (ENPAND_PT_DIM),
        .BRAM_DATA_WIDTH(BRAM_DATA_WIDTH),
        .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH)
    ) u_pfn (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axis_expire_tvalid(m_axis_expire_tvalid),
        .s_axis_expire_tready(m_axis_expire_tready),
        .s_axis_expire_tdata (m_axis_expire_tdata),
        .bram_clk            (bram_clk_b),
        .bram_rst            (bram_rst_b),
        .bram_addr           (bram_addr_b),
        .bram_en             (bram_en_b),
        .bram_rdata          (bram_rdata_b)
    );

    dualport_bram #(
        .DATA_WIDTH     (BRAM_DATA_WIDTH),
        .ADDR_WIDTH     (BRAM_ADDR_WIDTH),
        .MEM_FILE       ("NOTHING"),
        .MEM_FILE_LENGTH()
    ) voxelpoint_bram (
        .a_clk (bram_clk_a),
        .a_wr  (bram_wr_a),
        .a_en  (1'b1),
        .a_bwen(bram_bwen_a),
        .a_addr(bram_addr_a),
        .a_din (bram_wrdata_a),
        .a_dout(bram_porta_out),

        .b_clk (bram_clk_b),
        .b_wr  (1'b0),         // only read
        .b_en  (bram_en_b),
        .b_bwen(1'b0),         // only read
        .b_addr(bram_addr_b),
        .b_din (bram_addr_b),
        .b_dout(bram_rdata_b)
    );


endmodule
