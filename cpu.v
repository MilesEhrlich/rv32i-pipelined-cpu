module cpu (
    input wire clk,
    input wire rst
);
    // ---------- Fetch ----------
    reg  [31:0] pc;
    wire [31:0] instr;
    imem #(.FILE("program.hex")) u_imem (.addr(pc), .instr(instr));

    // ---------- Decode ----------
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    localparam OP_R      = 7'b0110011, OP_I     = 7'b0010011,
               OP_LOAD   = 7'b0000011, OP_STORE = 7'b0100011,
               OP_BRANCH = 7'b1100011, OP_JAL   = 7'b1101111,
               OP_JALR   = 7'b1100111, OP_LUI   = 7'b0110111,
               OP_AUIPC  = 7'b0010111;

    wire [31:0] imm;
    imm_gen u_imm (.instr(instr), .imm(imm));

    // ---------- Registers ----------
    reg  [31:0] wb_val;
    wire [31:0] rs1_val, rs2_val;
    wire reg_we = (opcode == OP_R)   || (opcode == OP_I)    ||
                  (opcode == OP_LOAD)|| (opcode == OP_JAL)  ||
                  (opcode == OP_JALR)|| (opcode == OP_LUI)  ||
                  (opcode == OP_AUIPC);

    regfile u_rf (.clk(clk), .we(reg_we & ~rst), .rs1(rs1), .rs2(rs2),
                  .rd(rd), .wd(wb_val), .rd1(rs1_val), .rd2(rs2_val));

    // ---------- ALU control ----------
    reg [3:0] alu_op;
    always @(*) begin
        if (opcode == OP_R || opcode == OP_I) begin
            case (funct3)
                3'b000: alu_op = (opcode == OP_R && funct7[5]) ? 4'd1 : 4'd0; // sub : add
                3'b001: alu_op = 4'd2;                     // sll
                3'b010: alu_op = 4'd3;                     // slt
                3'b011: alu_op = 4'd4;                     // sltu
                3'b100: alu_op = 4'd5;                     // xor
                3'b101: alu_op = funct7[5] ? 4'd7 : 4'd6;  // sra : srl
                3'b110: alu_op = 4'd8;                     // or
                default: alu_op = 4'd9;                    // and
            endcase
        end else begin
            alu_op = 4'd0;   // loads/stores: add to compute the address
        end
    end

    wire [31:0] alu_b = (opcode == OP_R) ? rs2_val : imm;
    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu (.a(rs1_val), .b(alu_b), .op(alu_op), .result(alu_y), .zero(alu_zero));

    // ---------- Memory ----------
    wire [31:0] load_val;
    dmem u_dmem (.clk(clk), .we((opcode == OP_STORE) & ~rst), .funct3(funct3),
                 .addr(alu_y), .wd(rs2_val), .rd(load_val));

    // ---------- Branches ----------
    reg take_branch;
    always @(*) begin
        case (funct3)
            3'b000:  take_branch = (rs1_val == rs2_val);                    // beq
            3'b001:  take_branch = (rs1_val != rs2_val);                    // bne
            3'b100:  take_branch = ($signed(rs1_val) <  $signed(rs2_val));  // blt
            3'b101:  take_branch = ($signed(rs1_val) >= $signed(rs2_val));  // bge
            3'b110:  take_branch = (rs1_val <  rs2_val);                    // bltu
            3'b111:  take_branch = (rs1_val >= rs2_val);                    // bgeu
            default: take_branch = 1'b0;
        endcase
    end

    // ---------- Next PC ----------
    wire [31:0] pc_plus4  = pc + 32'd4;
    wire [31:0] pc_target = pc + imm;
    reg  [31:0] next_pc;
    always @(*) begin
        case (opcode)
            OP_JAL:    next_pc = pc_target;
            OP_JALR:   next_pc = (rs1_val + imm) & ~32'd1;
            OP_BRANCH: next_pc = take_branch ? pc_target : pc_plus4;
            default:   next_pc = pc_plus4;
        endcase
    end

    // ---------- Write-back ----------
    always @(*) begin
        case (opcode)
            OP_LOAD:         wb_val = load_val;
            OP_JAL, OP_JALR: wb_val = pc_plus4;    // return address
            OP_LUI:          wb_val = imm;
            OP_AUIPC:        wb_val = pc_target;
            default:         wb_val = alu_y;
        endcase
    end

    always @(posedge clk) begin
        if (rst) pc <= 32'd0;
        else     pc <= next_pc;
    end
endmodule