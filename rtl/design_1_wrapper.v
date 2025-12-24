//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Wed Dec 24 14:04:00 2025
//Host        : LAPTOP-ZJ running 64-bit major release  (build 9200)
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (BRAM_PORTA_0_addr,
    BRAM_PORTA_0_clk,
    BRAM_PORTA_0_din,
    BRAM_PORTA_0_dout,
    BRAM_PORTA_0_en,
    BRAM_PORTA_0_rst,
    BRAM_PORTA_0_we,
    M_AXIS_MM2S_tdata,
    M_AXIS_MM2S_tkeep,
    M_AXIS_MM2S_tlast,
    M_AXIS_MM2S_tready,
    M_AXIS_MM2S_tvalid,
    S_AXIS_MM2S_CMD_tdata,
    S_AXIS_MM2S_CMD_tready,
    S_AXIS_MM2S_CMD_tvalid,
    S_AXIS_S2MM_CMD_tdata,
    S_AXIS_S2MM_CMD_tready,
    S_AXIS_S2MM_CMD_tvalid,
    S_AXIS_S2MM_tdata,
    S_AXIS_S2MM_tkeep,
    S_AXIS_S2MM_tlast,
    S_AXIS_S2MM_tready,
    S_AXIS_S2MM_tvalid,
    clk,
    rst_n);
  output [13:0]BRAM_PORTA_0_addr;
  output BRAM_PORTA_0_clk;
  output [127:0]BRAM_PORTA_0_din;
  input [127:0]BRAM_PORTA_0_dout;
  output BRAM_PORTA_0_en;
  output BRAM_PORTA_0_rst;
  output [15:0]BRAM_PORTA_0_we;
  output [127:0]M_AXIS_MM2S_tdata;
  output [15:0]M_AXIS_MM2S_tkeep;
  output M_AXIS_MM2S_tlast;
  input M_AXIS_MM2S_tready;
  output M_AXIS_MM2S_tvalid;
  input [71:0]S_AXIS_MM2S_CMD_tdata;
  output S_AXIS_MM2S_CMD_tready;
  input S_AXIS_MM2S_CMD_tvalid;
  input [71:0]S_AXIS_S2MM_CMD_tdata;
  output S_AXIS_S2MM_CMD_tready;
  input S_AXIS_S2MM_CMD_tvalid;
  input [127:0]S_AXIS_S2MM_tdata;
  input [15:0]S_AXIS_S2MM_tkeep;
  input S_AXIS_S2MM_tlast;
  output S_AXIS_S2MM_tready;
  input S_AXIS_S2MM_tvalid;
  input clk;
  input rst_n;

  wire [13:0]BRAM_PORTA_0_addr;
  wire BRAM_PORTA_0_clk;
  wire [127:0]BRAM_PORTA_0_din;
  wire [127:0]BRAM_PORTA_0_dout;
  wire BRAM_PORTA_0_en;
  wire BRAM_PORTA_0_rst;
  wire [15:0]BRAM_PORTA_0_we;
  wire [127:0]M_AXIS_MM2S_tdata;
  wire [15:0]M_AXIS_MM2S_tkeep;
  wire M_AXIS_MM2S_tlast;
  wire M_AXIS_MM2S_tready;
  wire M_AXIS_MM2S_tvalid;
  wire [71:0]S_AXIS_MM2S_CMD_tdata;
  wire S_AXIS_MM2S_CMD_tready;
  wire S_AXIS_MM2S_CMD_tvalid;
  wire [71:0]S_AXIS_S2MM_CMD_tdata;
  wire S_AXIS_S2MM_CMD_tready;
  wire S_AXIS_S2MM_CMD_tvalid;
  wire [127:0]S_AXIS_S2MM_tdata;
  wire [15:0]S_AXIS_S2MM_tkeep;
  wire S_AXIS_S2MM_tlast;
  wire S_AXIS_S2MM_tready;
  wire S_AXIS_S2MM_tvalid;
  wire clk;
  wire rst_n;

  design_1 design_1_i
       (.BRAM_PORTA_0_addr(BRAM_PORTA_0_addr),
        .BRAM_PORTA_0_clk(BRAM_PORTA_0_clk),
        .BRAM_PORTA_0_din(BRAM_PORTA_0_din),
        .BRAM_PORTA_0_dout(BRAM_PORTA_0_dout),
        .BRAM_PORTA_0_en(BRAM_PORTA_0_en),
        .BRAM_PORTA_0_rst(BRAM_PORTA_0_rst),
        .BRAM_PORTA_0_we(BRAM_PORTA_0_we),
        .M_AXIS_MM2S_tdata(M_AXIS_MM2S_tdata),
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
