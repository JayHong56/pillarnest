`timescale 1ns / 1ps

module tb (
);
    

reg clk; 
reg rst_n;

//==============================
// State encoding (5 states)
//==============================
localparam [4:0] IDLE   = 5'b0_0000;
localparam [4:0] W_ADDR = 5'b0_0010;
localparam [4:0] W_DATA = 5'b0_0100;
localparam [4:0] R_ADDR = 5'b0_1000;
localparam [4:0] R_DATA = 5'b1_0000;

reg [4:0] curr_state, next_state;

reg [3:0] start_cnt;

wire [22:0] btt  = 16*16;
wire        type = 1'b1;
wire [5:0]  dsa  = 6'd0;
wire        eof  = 1'b1;
wire        drr  = 1'b0;
wire [31:0] addr = 32'h0000_0000;
wire [3:0]  tag  = 4'b0;
wire [3:0]  rsvd = 4'b0;


wire [127:0] M_AXIS_MM2S_tdata   ;
wire [31:0]  M_AXIS_MM2S_tkeep   ;
wire         M_AXIS_MM2S_tlast   ;
wire         M_AXIS_MM2S_tready  ;
wire         M_AXIS_MM2S_tvalid  ;

// 读
wire [71:0]  S_AXIS_MM2S_CMD_tdata  = {rsvd, tag, addr, drr, eof, dsa, type, btt};
wire         S_AXIS_MM2S_CMD_tready;
reg          S_AXIS_MM2S_CMD_tvalid;

// 写
wire [71:0]  S_AXIS_S2MM_CMD_tdata  = {rsvd, tag, addr, drr, eof, dsa, type, btt};
wire         S_AXIS_S2MM_CMD_tready;
reg          S_AXIS_S2MM_CMD_tvalid;


wire [127:0] S_AXIS_S2MM_tdata   ;
wire [15:0]  S_AXIS_S2MM_tkeep    = 16'hffff;
wire         S_AXIS_S2MM_tlast   ;
wire         S_AXIS_S2MM_tready  ;
wire         S_AXIS_S2MM_tvalid  ;


reg [31:0] w_cnt;

initial begin
  clk = 1'b0;
  forever begin 
    #2.5 clk = ~clk;
    // clk = #2.5 !clk;

  end
end

initial begin
  rst_n = 1'b0;
  #100;
  rst_n = 1'b1;
end

//==============================
// State register
//==============================
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    curr_state <= IDLE;
  else
    curr_state <= next_state;
end

//==============================
// Next-state logic (combinational)
//==============================
always @(*) begin
  case (curr_state)

    IDLE: begin
      // 这里沿用你截图那种“计数到某值启动”的写法
      if (start_cnt == 4'b1111)
        next_state = W_ADDR;
      else
        next_state = IDLE;
    end
    

    W_ADDR: begin
      // 写命令通道握手成功 -> 进入写数据
      if ((S_AXIS_S2MM_CMD_tvalid == 1'b1) && (S_AXIS_S2MM_CMD_tready == 1'b1))
        next_state = W_DATA;
      else
        next_state = W_ADDR;
    end

    W_DATA: begin
      // 写数据最后一拍握手完成 -> 进入读地址
      if ((S_AXIS_S2MM_tlast == 1'b1) && (S_AXIS_S2MM_tready == 1'b1) && (S_AXIS_S2MM_tvalid == 1'b1))
        next_state = R_ADDR;
      else
        next_state = W_DATA;
    end

    R_ADDR: begin
      // 读命令通道握手成功 -> 进入读数据	
      if ((S_AXIS_MM2S_CMD_tvalid == 1'b1) && (S_AXIS_MM2S_CMD_tready == 1'b1))
        next_state = R_DATA;
      else
        next_state = R_ADDR;
    end

    R_DATA: begin
      // 读数据最后一拍握手完成 -> 回到空闲
      if ((M_AXIS_MM2S_tvalid == 1'b1) && (M_AXIS_MM2S_tready == 1'b1) && (M_AXIS_MM2S_tlast == 1'b1))
        next_state = IDLE;
      else
        next_state = R_DATA;
    end

    default: begin
      next_state = IDLE;
    end

  endcase
end

// 第一个代码块：计数器逻辑
always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        start_cnt <= 4'b0;
    end
    else begin
        if (curr_state == IDLE) begin
            start_cnt <= start_cnt + 4'b1;
        end
        else begin
            start_cnt <= 4'b0;
        end
    end
end

// 第二个代码块：AXI-Stream 命令通道有效信号控制
always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        S_AXIS_S2MM_CMD_tvalid <= 1'b0;
    end
    else begin
        if ((curr_state == IDLE) && (next_state == W_ADDR)) begin
            S_AXIS_S2MM_CMD_tvalid <= 1'b1;
        end
        else begin
          if ((S_AXIS_S2MM_CMD_tready == 1'b1) && (S_AXIS_S2MM_CMD_tvalid == 1'b1)) begin
			  S_AXIS_S2MM_CMD_tvalid <= 1'b0;
		  end
        end
    end
end

always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        S_AXIS_MM2S_CMD_tvalid <= 1'b0;
    end
    else begin
        if ((curr_state == W_DATA) && (next_state == R_ADDR)) begin
            S_AXIS_MM2S_CMD_tvalid <= 1'b1;
        end
        else begin
          if ((S_AXIS_MM2S_CMD_tready == 1'b1) && (S_AXIS_MM2S_CMD_tvalid == 1'b1)) begin
			  S_AXIS_MM2S_CMD_tvalid <= 1'b0;
		  end
        end
    end
end



always @(posedge clk) begin
    if (rst_n == 1'b0) begin
        w_cnt <= 32'd0;
    end
    else begin
        if (curr_state == W_DATA) begin
            // AXI-Stream 核心握手逻辑：只有双方都 Ready 且 Valid 时，数据才算传输成功
            if ((S_AXIS_S2MM_tready == 1'b1) && (S_AXIS_S2MM_tvalid == 1'b1)) begin
                w_cnt <= w_cnt + 32'd1;
            end
        end
        else begin
            w_cnt <= 32'd0;
        end
    end
end

assign S_AXIS_S2MM_tdata  = {4{w_cnt}};
assign S_AXIS_S2MM_tvalid = (curr_state == W_DATA) ? 1'b1 : 1'b0;
assign S_AXIS_S2MM_tlast = w_cnt == 32'd15;

assign M_AXIS_MM2S_tready = 1'b1;

wire [13:0] BRAM_PORTA_0_addr;
wire BRAM_PORTA_0_clk;
wire [127:0] BRAM_PORTA_0_din;
wire [127:0] BRAM_PORTA_0_dout;
wire BRAM_PORTA_0_en;
wire BRAM_PORTA_0_rst;
wire [15:0] BRAM_PORTA_0_we;


single_port_ram bram(
    .clka(BRAM_PORTA_0_clk),          // Clock
    .ena(BRAM_PORTA_0_en),           // Enable
    .rsta(BRAM_PORTA_0_rst),          // Reset (sync)
    .addra(BRAM_PORTA_0_addr),         // Address
    .dina(BRAM_PORTA_0_din),          // Data in
    .dout(BRAM_PORTA_0_dout),          // Data out
    .wea(BRAM_PORTA_0_we)            // Byte write enable (16 bytes)
);


design_1_wrapper design_1_wrapper_inst
      //  (.BRAM_PORTA_0_addr(BRAM_PORTA_0_addr),
      //   .BRAM_PORTA_0_clk(BRAM_PORTA_0_clk),
      //   .BRAM_PORTA_0_din(BRAM_PORTA_0_din),
      //   .BRAM_PORTA_0_dout(BRAM_PORTA_0_dout),
      //   .BRAM_PORTA_0_en(BRAM_PORTA_0_en),
      //   .BRAM_PORTA_0_rst(BRAM_PORTA_0_rst),
      //   .BRAM_PORTA_0_we(BRAM_PORTA_0_we),

       (.M_AXIS_MM2S_tdata(M_AXIS_MM2S_tdata),
        .M_AXIS_MM2S_tkeep(M_AXIS_MM2S_tkeep),
        .M_AXIS_MM2S_tlast(M_AXIS_MM2S_tlast),
        .M_AXIS_MM2S_tready(M_AXIS_MM2S_tready),
        .M_AXIS_MM2S_tvalid(M_AXIS_MM2S_tvalid),

        .S_AXIS_MM2S_CMD_tdata(S_AXIS_MM2S_CMD_tdata),
        .S_AXIS_MM2S_CMD_tready(S_AXIS_MM2S_CMD_tready),
        .S_AXIS_MM2S_CMD_tvalid(S_AXIS_MM2S_CMD_tvalid),
        .S_AXIS_S2MM_CMD_tdata(S_AXIS_S2MM_CMD_tdata),
        .S_AXIS_S2MM_CMD_tready(S_AXIS_S2MM_CMD_tready),
        .S_AXIS_S2MM_CMD_tvalid(S_AXIS_S2MM_CMD_tvalid),


        .S_AXIS_S2MM_tdata(S_AXIS_S2MM_tdata),
        .S_AXIS_S2MM_tkeep(S_AXIS_S2MM_tkeep),
        .S_AXIS_S2MM_tlast(S_AXIS_S2MM_tlast),
        .S_AXIS_S2MM_tready(S_AXIS_S2MM_tready),
        .S_AXIS_S2MM_tvalid(S_AXIS_S2MM_tvalid),
        .clk(clk),
        .rst_n(rst_n));


endmodule