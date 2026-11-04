module imem #(parameter WORDS = 1024, parameter FILE = "program.hex") (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    initial $readmemh(FILE, mem);
    assign instr = mem[addr[AW+1:2]];
endmodule