module voxel_coor #(
    parameter integer PIPE_STAGES = 4  // 固定流水线级数（= 固定延迟拍数）
) (
    input clk,
    input rst_n,

    // AXI Stream Slave (Input)  <- 来自“读BRAM的FIFO”的AXIS
    input  [127:0] S_AXIS_TDATA,
    input  [ 15:0] S_AXIS_TKEEP,
    input          S_AXIS_TLAST,
    input          S_AXIS_TVALID,
    output         S_AXIS_TREADY,

    // AXI Stream Master (Output)
    output [127:0] M_AXIS_TDATA,
    output [ 15:0] M_AXIS_TKEEP,
    output         M_AXIS_TLAST,
    output         M_AXIS_TVALID,
    input          M_AXIS_TREADY
);

    // ----------------------------
    // pipeline registers
    // stage[i] holds one point
    // ----------------------------
    reg  [          127:0] p_data                              [0:PIPE_STAGES-1];
    reg  [           15:0] p_keep                              [0:PIPE_STAGES-1];
    reg                    p_last                              [0:PIPE_STAGES-1];
    reg                    p_drop                              [0:PIPE_STAGES-1];
    reg                    p_valid                             [0:PIPE_STAGES-1];

    // ready chain
    wire [0:PIPE_STAGES-1] p_ready;

    // ----------------------------
    // Output interface is driven by last stage
    // ----------------------------
    wire                   last_valid = p_valid[PIPE_STAGES-1];
    wire                   last_drop = p_drop[PIPE_STAGES-1];

    // 只有不drop的点才对外valid
    assign M_AXIS_TVALID = last_valid && ~last_drop;
    assign M_AXIS_TDATA  = p_data[PIPE_STAGES-1];
    assign M_AXIS_TKEEP  = p_keep[PIPE_STAGES-1];
    assign M_AXIS_TLAST  = p_last[PIPE_STAGES-1];

    // last stage “被消费”的条件：
    // - drop点：无条件内部消费（不依赖M_READY）
    // - keep点：要等 M_AXIS_TREADY 握手成功
    wire last_consumed = last_valid && (last_drop || (M_AXIS_TREADY && ~last_drop));

    // last stage 可接收前一级推进的条件：
    // - 自己空
    // - 或者本拍会被消费掉
    assign p_ready[PIPE_STAGES-1] = ~p_valid[PIPE_STAGES-1] || last_consumed;

    // ----------------------------
    // Intermediate stage ready: standard elastic pipeline rule
    // stage i can accept new data if it is empty OR it will advance this cycle
    // ----------------------------
    genvar gi;
    generate
        for (gi = 0; gi < PIPE_STAGES - 1; gi = gi + 1) begin : GEN_READY
            assign p_ready[gi] = ~p_valid[gi] || p_ready[gi+1];
        end
    endgenerate

    // Input ready is stage0 ready
    assign S_AXIS_TREADY = p_ready[0];

    // ----------------------------
    // Placeholder “per-stage processing”
    // You can modify data/keep/last/drop between stages here.
    // For now: pass-through.
    // ----------------------------
    // stage_in_* are the values that will be loaded into stage i+1
    wire [127:0] stage_in_data[0:PIPE_STAGES-2];
    wire [ 15:0] stage_in_keep[0:PIPE_STAGES-2];
    wire         stage_in_last[0:PIPE_STAGES-2];
    wire         stage_in_drop[0:PIPE_STAGES-2];

    generate
        for (gi = 0; gi < PIPE_STAGES - 1; gi = gi + 1) begin : GEN_STAGE_COMB
            // 默认直通；你可以在这里插入第gi级到gi+1级的组合逻辑（固定延迟流水）
            // TODO: stage processing here (e.g., coordinate transform, voxel calc, etc.)
            assign stage_in_data[gi] = p_data[gi];
            assign stage_in_keep[gi] = p_keep[gi];
            assign stage_in_last[gi] = p_last[gi];

            // TODO: boundary check can be done at any stage, produce a drop flag.
            //       You can set something like: p_drop[gi] | out_of_bounds(...)
            assign stage_in_drop[gi] = p_drop[gi];  // placeholder
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < PIPE_STAGES; i = i + 1) begin
                p_data[i]  <= 128'd0;
                p_keep[i]  <= 16'd0;
                p_last[i]  <= 1'b0;
                p_drop[i]  <= 1'b0;
                p_valid[i] <= 1'b0;
            end
        end else begin
            // ---- stage 0 load from S_AXIS
            if (p_ready[0]) begin
                if (S_AXIS_TVALID) begin
                    p_data[0]  <= S_AXIS_TDATA;
                    p_keep[0]  <= S_AXIS_TKEEP;
                    p_last[0]  <= S_AXIS_TLAST;
                    p_drop[0]  <= 1'b0;  // TODO: if you can early-drop at stage0, compute here
                    p_valid[0] <= 1'b1;
                end else begin
                    p_valid[0] <= 1'b0;
                end
            end

            // ---- stages 1..N-1 shift when ready
            for (i = 1; i < PIPE_STAGES; i = i + 1) begin
                if (p_ready[i]) begin
                    if (p_valid[i-1]) begin
                        p_data[i]  <= stage_in_data[i-1];
                        p_keep[i]  <= stage_in_keep[i-1];
                        p_last[i]  <= stage_in_last[i-1];
                        p_drop[i]  <= stage_in_drop[i-1];
                        p_valid[i] <= 1'b1;
                    end else begin
                        p_valid[i] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
