module alu (
    input  wire [31:0] a, b,
    input  wire [3:0]  op,
    output reg  [31:0] result,
    output wire        zero
);
    localparam OP_ADD = 4'd0, OP_SUB = 4'd1, OP_SLL = 4'd2, OP_SLT = 4'd3,
               OP_SLTU = 4'd4, OP_XOR = 4'd5, OP_SRL = 4'd6, OP_SRA = 4'd7,
               OP_OR = 4'd8, OP_AND = 4'd9;

    always @(*) begin
        case (op)
            OP_ADD:  result = a + b;
            OP_SUB:  result = a - b;
            OP_SLL:  result = a << b[4:0];
            OP_SLT:  result = {31'd0, $signed(a) < $signed(b)};
            OP_SLTU: result = {31'd0, a < b};
            OP_XOR:  result = a ^ b;
            OP_SRL:  result = a >> b[4:0];
            OP_SRA:  result = $signed(a) >>> b[4:0];
            OP_OR:   result = a | b;
            OP_AND:  result = a & b;
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);
endmodule