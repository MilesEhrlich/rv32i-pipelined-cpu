module alu (
    input  wire [31:0] a, b,
    input  wire [2:0]  op,
    output reg  [31:0] result,
    output wire        zero     // 1 when result is 0 (used for branches later)
);
    localparam OP_ADD = 3'd0,
               OP_SUB = 3'd1,
               OP_AND = 3'd2,
               OP_OR  = 3'd3,
               OP_XOR = 3'd4;

    always @(*) begin
        case (op)
            OP_ADD:  result = a + b;
            OP_SUB:  result = a - b;
            OP_AND:  result = a & b;
            OP_OR:   result = a | b;
            OP_XOR:  result = a ^ b;
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);
endmodule