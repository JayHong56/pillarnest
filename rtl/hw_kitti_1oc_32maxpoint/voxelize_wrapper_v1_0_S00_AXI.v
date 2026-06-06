`timescale 1 ns / 1 ps

module voxelize_wrapper_v1_0_S00_AXI #(
    // AXI4LITE ����
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5,
    parameter integer DRAM_DATA_WIDTH    = 128,
    parameter integer DRAM_ADDR_WIDTH    = 23,
    // Voxelize ����λ������
    parameter integer AXIS_DATA_WIDTH    = 128
) (
    // -----------------------------------------------------------
    // �������������ⲿģ������ö˿�
    // -----------------------------------------------------------
    output wire [31:0] write_base_addr_out,  // <--- dynamic output base address

    // -----------------------------------------------------------
    // PL clear control ports
    // -----------------------------------------------------------
    output wire        clear_start_out,
    input  wire        clear_done_in,
    input  wire        clear_busy_in,
    input  wire        clear_error_in,
    input  wire        output_path_idle_in,
    input  wire        output_path_error_in,

    // -----------------------------------------------------------
    // AXI4-Stream Slave (������������)
    // -----------------------------------------------------------
    input  wire [  DRAM_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [DRAM_DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  wire                         s_axis_tlast,

    output wire [  AXIS_DATA_WIDTH-1:0] m_0_axis_tdata,
    output wire                         m_0_axis_tvalid,
    output wire [AXIS_DATA_WIDTH/8-1:0] m_0_axis_tkeep,        // ���� TKEEP �ź�
    input  wire                         m_0_axis_tready,       // �ڲ��ݲ�֧�ֱ�ѹ����Ԥ��
    output wire                         m_0_axis_tlast,        // ��֡�������׽������� flush_done ������
    // ���ͨ�������Voxel ��������Ч��־��
    output wire [               11-1:0] m_0_axis_voxel_x,
    output wire [               11-1:0] m_0_axis_voxel_y,
    output wire                         m_0_axis_voxel_valid,  // ���ͨ�������Voxel ��������Ч��־��
    input  wire                         m_0_axis_voxel_ready,

    // -----------------------------------------------------------
    // AXI-Stream Command Interface (���ӵ� DataMover)
    // -----------------------------------------------------------
    output wire        m_axis_cmd_tvalid,
    input  wire        m_axis_cmd_tready,
    output wire [71:0] m_axis_cmd_tdata,

    // -----------------------------------------------------------
    // AXI4-Lite Slave �ӿ�
    // -----------------------------------------------------------
    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,
    input  wire [    C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input  wire [                       2 : 0] S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,
    input  wire [    C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,
    output wire [                       1 : 0] S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,
    input  wire [    C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input  wire [                       2 : 0] S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,
    output wire [    C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [                       1 : 0] S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY
);




    // AXI4LITE �ź�
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg                            axi_awready;
    reg                            axi_wready;
    reg [                   1 : 0] axi_bresp;
    reg                            axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg                            axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [                   1 : 0] axi_rresp;
    reg                            axi_rvalid;

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH / 32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 2;

    reg     [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg     [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg     [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;
    reg     [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;
    reg     [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;
    wire                             slv_reg_rden;
    wire                             slv_reg_wren;
    reg     [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer                          byte_index;
    reg                              aw_en;

    // ��������
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
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

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awaddr <= 0;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awaddr <= S_AXI_AWADDR;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    // === ���� Start ���� ===
    // ���������� slv_reg0 �� bit0 д�� 1 ʱ������һ��ʱ�����ڵ�����
    wire start_pulse = (slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) && S_AXI_WSTRB[0] && S_AXI_WDATA[0]);
    wire clear_done_by_sw = (slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) && S_AXI_WSTRB[0] && S_AXI_WDATA[2]);
    wire voxelize_done;
    reg done_latched;
    reg busy_latched;
    reg error_latched;
    reg core_done_seen;

    // Accept a new frame only when the previous frame is not busy, the clear
    // writer is idle, and the previous normal S2MM output write path has fully
    // drained. This prevents the next frame's clear writer from stealing the
    // DataMover while old normal writes/statuses are still pending.
    wire start_accept = start_pulse && !busy_latched && !clear_busy_in && output_path_idle_in;

    // PS start first launches PL clear. The voxelize core is started only
    // after clear_done_in is returned by s2mm_clear_writer.
    assign clear_start_out = start_accept;

    reg core_start_pulse;
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            core_start_pulse <= 1'b0;
        end else begin
            core_start_pulse <= clear_done_in && !clear_error_in;
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
            slv_reg4 <= 0;
        end else begin
            // slv_reg0 �� bit0 �Զ����㣬�����֡�����λ����д�롣
            if (slv_reg_wren) begin
                case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    3'h0: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH / 8) - 1; byte_index = byte_index + 1)
                        if (S_AXI_WSTRB[byte_index] == 1) slv_reg0[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    3'h1:
                    for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH / 8) - 1; byte_index = byte_index + 1)
                    if (S_AXI_WSTRB[byte_index] == 1) slv_reg1[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    3'h2:
                    for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH / 8) - 1; byte_index = byte_index + 1)
                    if (S_AXI_WSTRB[byte_index] == 1) slv_reg2[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    3'h3:
                    for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH / 8) - 1; byte_index = byte_index + 1)
                    if (S_AXI_WSTRB[byte_index] == 1) slv_reg3[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    3'h4:
                    for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH / 8) - 1; byte_index = byte_index + 1)
                    if (S_AXI_WSTRB[byte_index] == 1) slv_reg4[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    default: ;
                endcase
            end
            // �Զ���� slv_reg0 �� bit0 (����λ)
            slv_reg0[0] <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // Sticky done/busy status for PS polling
    // m_axis_pfn_flush_done is converted to voxelize_done by core.
    // done_latched stays high until PS writes 1 to reg0[2], so PS will not miss
    // the 1-cycle done pulse.
    // ------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            done_latched   <= 1'b0;
            busy_latched   <= 1'b0;
            error_latched  <= 1'b0;
            core_done_seen <= 1'b0;
        end else begin
            if (start_accept) begin
                done_latched   <= 1'b0;
                busy_latched   <= 1'b1;
                error_latched  <= 1'b0;
                core_done_seen <= 1'b0;
            end else begin
                if (clear_done_by_sw) begin
                    done_latched  <= 1'b0;
                    error_latched <= 1'b0;
                end

                if (voxelize_done) begin
                    core_done_seen <= 1'b1;
                end

                if (clear_done_in && clear_error_in) begin
                    done_latched   <= 1'b1;
                    busy_latched   <= 1'b0;
                    error_latched  <= 1'b1;
                    core_done_seen <= 1'b0;
                end else if (output_path_error_in && busy_latched) begin
                    done_latched   <= 1'b1;
                    busy_latched   <= 1'b0;
                    error_latched  <= 1'b1;
                    core_done_seen <= 1'b0;
                end else if ((voxelize_done || core_done_seen) && output_path_idle_in) begin
                    done_latched   <= 1'b1;
                    busy_latched   <= 1'b0;
                    core_done_seen <= 1'b0;
                end
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid <= 0;
            axi_bresp  <= 2'b0;
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

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
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

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
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

    wire voxelize_idle_rd_ddr;
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;


    assign write_base_addr_out = slv_reg3;
    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            // ��ȡ slv_reg0 ʱ�����ڲ��� idle ״̬ӳ�䵽 Bit 1
            // bit0=start(read as 0)
            // bit1=voxelize MM2S cmd idle, bit2=done_latched, bit3=busy_latched
            // bit4=clear_busy, bit5=clear_error/status_error
            // bit6=output_path_idle, bit7=core_done_seen
            3'h0   : reg_data_out <= {slv_reg0[31:8], core_done_seen, output_path_idle_in, error_latched, clear_busy_in, busy_latched, done_latched, voxelize_idle_rd_ddr, 1'b0};
            3'h1   : reg_data_out <= slv_reg1;
            3'h2   : reg_data_out <= slv_reg2;
            3'h3   : reg_data_out <= slv_reg3;
            3'h4   : reg_data_out <= slv_reg4;
            default : reg_data_out <= 0;
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rdata <= 0;
        end else begin
            if (slv_reg_rden) begin
                axi_rdata <= reg_data_out;
            end
        end
    end

    // =========================================================================
    // ʵ�������ĵ� Voxelize ģ��
    // =========================================================================
    voxelize #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .DRAM_DATA_WIDTH(DRAM_DATA_WIDTH),
        .DRAM_ADDR_WIDTH(DRAM_ADDR_WIDTH)
        // ���������� voxelize �ڲ���Ĭ��ֵ
    ) u_voxelize_core (
        .aclk   (S_AXI_ACLK),
        .aresetn(S_AXI_ARESETN),

        // --- ��̬���ò��� ---
        // 0x04: ӳ��Ϊ DDR ����ʼ��ַ
        .base_addr_in  (slv_reg1),
        // 0x08: ӳ��Ϊ���ֽ��� (ȡ��23λ)
        .frame_bytes_in(slv_reg2[22:0]),


        // --- AXI-Stream Slave ---
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tlast (s_axis_tlast),

        .m_0_axis_tdata      (m_0_axis_tdata),
        .m_0_axis_tvalid     (m_0_axis_tvalid),
        .m_0_axis_tkeep      (m_0_axis_tkeep),        // ���� TKEEP �ź�
        .m_0_axis_tready     (m_0_axis_tready),       // �ڲ��ݲ�֧�ֱ�ѹ����Ԥ��
        .m_0_axis_tlast      (m_0_axis_tlast),        // ��֡�������׽������� flush_done ������
        .m_0_axis_voxel_x    (m_0_axis_voxel_x),
        .m_0_axis_voxel_y    (m_0_axis_voxel_y),
        .m_0_axis_voxel_valid(m_0_axis_voxel_valid),  // ���ͨ�������Voxel ��������Ч��־��
        .m_0_axis_voxel_ready(m_0_axis_voxel_ready),
        // --- ���ƽӿ� ---
        // start_pulse ��ͨ��д�Ĵ��������ĵ����ڸߵ�ƽ
        .start_req        (core_start_pulse),
        // voxelize_idle_rd_ddr ���� AXI �������Ա�������ѯ
        .mm2s_cmd_idle    (voxelize_idle_rd_ddr),
        .voxelize_done    (voxelize_done),
        // --- DataMover Command ---
        .m_axis_cmd_tvalid(m_axis_cmd_tvalid),
        .m_axis_cmd_tready(m_axis_cmd_tready),
        .m_axis_cmd_tdata (m_axis_cmd_tdata)
    );

endmodule
