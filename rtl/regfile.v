module regfile (
    input  wire        clk,
    input  wire        we,          // write enable
    input  wire [4:0]  rs1, rs2, rd,
    input  wire [31:0] wd,          // write data
    output wire [31:0] rd1, rd2     // read data
);
    reg [31:0] regs [0:31];
    integer i;
`ifndef SYNTHESIS
    // Simulation only: start from zeros instead of X. Hardware doesn't need
    // it (x0 reads as 0 through the mux below; software initializes the rest)
    // and an ASIC has no way to preload flip-flops.
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 0;
`endif

    always @(posedge clk)
        if (we && rd != 0) regs[rd] <= wd;    // x0 is never written

    assign rd1 = (rs1 == 0) ? 32'd0 : regs[rs1];
    assign rd2 = (rs2 == 0) ? 32'd0 : regs[rs2];
endmodule