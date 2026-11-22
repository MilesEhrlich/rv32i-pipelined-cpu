// Data memory, block-RAM friendly: one synchronous port on the rising edge.
// Stores are written at the end of their cycle. Loads return data the cycle
// AFTER the address is presented, so the CPU spends 2 cycles on a load.
// (An earlier version clocked this on the falling edge to keep loads at 1
// cycle, but the address and data paths need ~30 ns + ~20 ns, far more than
// the 18.5 ns half-cycle at 27 MHz; it failed on hardware.)
//
// Built as four independent 8-bit-wide memories, one per byte lane, each with
// a plain write enable, so every block RAM is a simple 2048x8 memory with no
// reliance on the synthesizer's byte-enable mapping. Lane k is preloaded from
// FILE.lanek (see sw/bin2hex.py).
module dmem #(parameter WORDS = 1024, parameter FILE = "") (
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  funct3,      // access size and signedness
    input  wire [31:0] addr,
    input  wire [31:0] wd,
    output reg  [31:0] rd,
    output wire [31:0] word_out    // raw registered word (pipeline extracts in MEM)
);
    localparam AW = $clog2(WORDS);
    wire [AW-1:0] idx = addr[AW+1:2];
    wire [1:0]    off = addr[1:0];

    // Byte enables and lane-aligned write data
    reg [3:0]  be;
    reg [31:0] wdata;
    always @(*) begin
        case (funct3[1:0])
            2'b00:   begin be = 4'b0001 << off;             wdata = {4{wd[7:0]}};  end // sb
            2'b01:   begin be = off[1] ? 4'b1100 : 4'b0011; wdata = {2{wd[15:0]}}; end // sh
            default: begin be = 4'b1111;                    wdata = wd;            end // sw
        endcase
    end

    wire [31:0] word;
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
        assign word[8*k +: 8] = q;
    end endgenerate

    assign word_out = word;

    // Loads: pick and extend the addressed byte/half from the registered word
    wire [31:0] shifted = word >> {off, 3'b000};
    always @(*) begin
        case (funct3)
            3'b000:  rd = {{24{shifted[7]}},  shifted[7:0]};    // lb
            3'b001:  rd = {{16{shifted[15]}}, shifted[15:0]};   // lh
            3'b100:  rd = {24'd0, shifted[7:0]};                // lbu
            3'b101:  rd = {16'd0, shifted[15:0]};               // lhu
            default: rd = word;                                 // lw
        endcase
    end
endmodule
