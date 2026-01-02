`timescale 1ns / 1ps

module single_port_ram (
    input              clka,          // Clock
    input              ena,           // Enable
    input              rsta,          // Reset (sync)
    input      [13:0]  addra,         // Address
    input      [127:0] dina,          // Data in
    output reg [127:0] dout,          // Data out
    input      [15:0]  wea            // Byte write enable (16 bytes)
);

    parameter DATA_WIDTH = 128;
    parameter ADDR_WIDTH = 14;
    parameter RAM_DEPTH  = 1 << ADDR_WIDTH;

    // BRAM style hint (Xilinx/Intel都能综合，工具可能忽略/识别)
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

    integer i;

    // 可选：仿真初始化（综合一般会忽略，或由工具支持 init）
    initial begin
        for (i = 0; i < RAM_DEPTH; i = i + 1)
            mem[i] = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clka) begin
        if (rsta) begin
            dout <= {DATA_WIDTH{1'b0}};
        end else if (ena) begin
            // 先读：同步读（BRAM常见行为：读数据在时钟沿更新）
            dout <= mem[addra];

            // 写：wea任意位为1则写（字节粒度）
            if (|wea) begin
                if (wea[0])  mem[addra][7:0]     <= dina[7:0];
                if (wea[1])  mem[addra][15:8]    <= dina[15:8];
                if (wea[2])  mem[addra][23:16]   <= dina[23:16];
                if (wea[3])  mem[addra][31:24]   <= dina[31:24];
                if (wea[4])  mem[addra][39:32]   <= dina[39:32];
                if (wea[5])  mem[addra][47:40]   <= dina[47:40];
                if (wea[6])  mem[addra][55:48]   <= dina[55:48];
                if (wea[7])  mem[addra][63:56]   <= dina[63:56];
                if (wea[8])  mem[addra][71:64]   <= dina[71:64];
                if (wea[9])  mem[addra][79:72]   <= dina[79:72];
                if (wea[10]) mem[addra][87:80]   <= dina[87:80];
                if (wea[11]) mem[addra][95:88]   <= dina[95:88];
                if (wea[12]) mem[addra][103:96]  <= dina[103:96];
                if (wea[13]) mem[addra][111:104] <= dina[111:104];
                if (wea[14]) mem[addra][119:112] <= dina[119:112];
                if (wea[15]) mem[addra][127:120] <= dina[127:120];

                // 如果你希望写后立刻读到新数据（write-first），可以加这一句：
                // dout <= mem[addra];  // 或者直接 dout <= (写后的组合结果)
            end
        end
    end

    integer i;
    initial begin
        // $readmemb("E:/verilog/pillarnest/rtl/pointcloud/points_bits_32.txt", mem);
        // for(i=0; i < RAM_DEPTH; i = i + 1) begin
        //     mem[i] = 8'h00;
        // end
    end


endmodule
