`timescale 1ps/1ps

module preprocessor_tb;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg [127:0] S_AXIS_TDATA;
    reg [15:0]  S_AXIS_TKEEP;
    reg         S_AXIS_TLAST;
    reg         S_AXIS_TVALID;
    wire        S_AXIS_TREADY;
    wire [127:0] M_AXIS_TDATA;
    wire [15:0]  M_AXIS_TKEEP;
    wire         M_AXIS_TLAST;
    wire         M_AXIS_TVALID;
    reg          M_AXIS_TREADY;

    // Instantiate the preprocessor
    preprocessor uut (
        .clk(clk),
        .rst_n(rst_n),
        .S_AXIS_TDATA(S_AXIS_TDATA),
        .S_AXIS_TKEEP(S_AXIS_TKEEP),
        .S_AXIS_TLAST(S_AXIS_TLAST),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TKEEP(M_AXIS_TKEEP),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        .M_AXIS_TREADY(M_AXIS_TREADY)
    );

    // Clock generation
    always begin
        #5 clk = ~clk;  // 100 MHz clock
    end

    // Test stimulus
    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        S_AXIS_TDATA = 128'b0;
        S_AXIS_TKEEP = 16'b0;
        S_AXIS_TLAST = 0;
        S_AXIS_TVALID = 0;
        M_AXIS_TREADY = 1;

        // Reset the DUT
        #10;
        rst_n = 1;
        #10;
        
        // Stimulus for testing
        S_AXIS_TVALID = 1;
        S_AXIS_TDATA = 128'h3F800000000000000000000000000000; // Random data for testing
        S_AXIS_TKEEP = 16'hFFFF;
        S_AXIS_TLAST = 1;

        // Wait for some cycles to see if the output changes
        #20;
        
        // Test another set of inputs
        S_AXIS_TDATA = 128'h40000000000000000000000000000000; // Another test input
        S_AXIS_TKEEP = 16'hFFFF;
        S_AXIS_TLAST = 0;

        // Wait and then de-assert valid signal
        #20;
        S_AXIS_TVALID = 0;

        // Finish the simulation
        #20;
        $finish;
    end

    // Monitor signals
    initial begin
        $monitor("At time %t, S_AXIS_TDATA = %h, M_AXIS_TDATA = %h, S_AXIS_TREADY = %b, M_AXIS_TVALID = %b", $time, S_AXIS_TDATA, M_AXIS_TDATA, S_AXIS_TREADY, M_AXIS_TVALID);
    end

endmodule

