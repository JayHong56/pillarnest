module hash_bucket_bram #(
    parameter integer WIDTH = 64,
    parameter integer DEPTH = 64,
    parameter integer AW    = $clog2(DEPTH)
)(
    input  wire             clk,

    input  wire [AW-1:0]    a_addr,
    input  wire             a_we,
    input  wire [WIDTH-1:0] a_wdata,
    output reg  [WIDTH-1:0] a_rdata,

    input  wire [AW-1:0]    b_addr,
    input  wire             b_we,
    input  wire [WIDTH-1:0] b_wdata,
    output reg  [WIDTH-1:0] b_rdata
);
    (* ram_style="block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    integer idx;
    initial begin
        for (idx = 0; idx < (1 << AW); idx = idx + 1) begin
            mem[idx] = {WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (b_we && (b_addr == a_addr)) begin
            a_rdata <= b_wdata;     
        end else begin
            a_rdata <= mem[a_addr];  
        end
        
        if (a_we) mem[a_addr] <= a_wdata;

        if (b_we) mem[b_addr] <= b_wdata;
        b_rdata <= mem[b_addr]; 
        
    end
endmodule