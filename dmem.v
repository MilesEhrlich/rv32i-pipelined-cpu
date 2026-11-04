module dmem #(parameter WORDS = 1024) (
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  funct3,      // access size and signedness
    input  wire [31:0] addr,
    input  wire [31:0] wd,
    output reg  [31:0] rd
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 0;

    wire [AW-1:0] idx     = addr[AW+1:2];
    wire [1:0]    off     = addr[1:0];
    wire [31:0]   word    = mem[idx];
    wire [31:0]   shifted = word >> {off, 3'b000};

    // Loads
    always @(*) begin
        case (funct3)
            3'b000:  rd = {{24{shifted[7]}},  shifted[7:0]};    // lb
            3'b001:  rd = {{16{shifted[15]}}, shifted[15:0]};   // lh
            3'b100:  rd = {24'd0, shifted[7:0]};                // lbu
            3'b101:  rd = {16'd0, shifted[15:0]};               // lhu
            default: rd = word;                                 // lw
        endcase
    end

    // Stores
    always @(posedge clk) begin
        if (we) begin
            case (funct3)
                3'b000: case (off)                              // sb
                    2'd0: mem[idx][7:0]   <= wd[7:0];
                    2'd1: mem[idx][15:8]  <= wd[7:0];
                    2'd2: mem[idx][23:16] <= wd[7:0];
                    2'd3: mem[idx][31:24] <= wd[7:0];
                endcase
                3'b001: if (off[1]) mem[idx][31:16] <= wd[15:0]; // sh
                        else        mem[idx][15:0]  <= wd[15:0];
                default: mem[idx] <= wd;                         // sw
            endcase
        end
    end
endmodule