// Instruction memory with a synchronous (clocked) read so it maps onto FPGA
// block RAM. The CPU feeds it next_pc, so the instruction for the new PC is
// ready right after the same clock edge that updates the PC.
module imem #(parameter WORDS = 1024, parameter FILE = "program.hex") (
    input  wire        clk,
    input  wire [31:0] addr,
    output reg  [31:0] instr
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    initial $readmemh(FILE, mem);
    always @(posedge clk) instr <= mem[addr[AW+1:2]];
endmodule
