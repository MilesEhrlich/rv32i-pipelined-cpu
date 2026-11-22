// Synchronous single-port RAM with byte enables, for FPGA block RAM.
// Built as four 8-bit lanes, each a plain block RAM with its own write
// enable; lane k is preloaded from FILE.lanek (see sw/bin2hex.py).
module bram_be #(parameter WORDS = 2048, parameter FILE = "") (
    input  wire        clk,
    input  wire [31:0] addr,      // byte address
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] wdata,
    output wire [31:0] rdata      // word at last cycle's addr
);
    localparam AW = $clog2(WORDS);
    wire [AW-1:0] idx = addr[AW+1:2];
    genvar k;
    generate for (k = 0; k < 4; k = k + 1) begin : lane
        localparam [7:0] DIGIT = 8'd48 + k;                  // ASCII '0' + k
        reg [7:0] mem [0:WORDS-1];
        reg [7:0] q;
        integer i;
        initial begin
`ifndef SYNTHESIS
            for (i = 0; i < WORDS; i = i + 1) mem[i] = 0;   // sim: zeros, not X
`endif
            if (FILE != "") $readmemh({FILE, ".lane", DIGIT}, mem);
        end
        always @(posedge clk) begin
            if (we && be[k]) mem[idx] <= wdata[8*k +: 8];
            q <= mem[idx];
        end
        assign rdata[8*k +: 8] = q;
    end endgenerate
endmodule
