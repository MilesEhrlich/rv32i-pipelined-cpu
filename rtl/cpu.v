module cpu #(
    parameter PROGRAM   = "",             // hex file loaded into instruction memory
    parameter DATA_FILE = "",             // optional preload of data memory
    parameter MEM_WORDS = 2048            // 8 KB each for imem and dmem
) (
    input  wire        clk,
    input  wire        rst,
    // Memory-mapped I/O bus: any access with addr[31:28] == 4'h1
    output wire        mmio_we,      // store to an I/O address this cycle
    output wire        mmio_re,      // load from an I/O address this cycle
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    input  wire [31:0] mmio_rdata,
    output wire        retire        // 1 when an instruction completes this cycle
);
    // ---------- Fetch ----------
    reg  [31:0] pc;
    reg  [31:0] next_pc;            // computed below
    wire [31:0] pc_next_eff;        // next_pc, or pc while a load waits; drives imem
    wire [31:0] alu_y;              // ALU result (also the load/store address)
    wire        is_mmio = (alu_y[31:28] == 4'h1);   // I/O space: 0x1xxxxxxx
    wire [31:0] instr;
    imem #(.WORDS(MEM_WORDS), .FILE(PROGRAM)) u_imem (.clk(clk), .addr(rst ? 32'd0 : pc_next_eff), .instr(instr));

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

    // Loads from data memory take 2 cycles: the block RAM returns data one
    // clock after it sees the address. In the first cycle we stall (hold the
    // PC, skip write-back); in the second, load_wait is set and data is ready.
    wire is_dmem_load = (opcode == OP_LOAD) && !is_mmio;
    reg  load_wait;
    wire stall = is_dmem_load && !load_wait;
    always @(posedge clk) load_wait <= rst ? 1'b0 : stall;

    regfile u_rf (.clk(clk), .we(reg_we & ~stall & ~rst), .rs1(rs1), .rs2(rs2),
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
    wire        alu_zero;
    alu u_alu (.a(rs1_val), .b(alu_b), .op(alu_op), .result(alu_y), .zero(alu_zero));

    // ---------- Memory ----------
    wire [31:0] dmem_val;
    dmem #(.WORDS(MEM_WORDS), .FILE(DATA_FILE)) u_dmem (
        .clk(clk), .we((opcode == OP_STORE) & ~is_mmio & ~rst), .funct3(funct3),
        .addr(alu_y), .wd(rs2_val), .rd(dmem_val));

    assign mmio_we    = (opcode == OP_STORE) & is_mmio & ~rst;
    assign mmio_re    = (opcode == OP_LOAD)  & is_mmio & ~rst;
    assign mmio_addr  = alu_y;
    assign mmio_wdata = rs2_val;
    wire [31:0] load_val = is_mmio ? mmio_rdata : dmem_val;

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

    assign pc_next_eff = stall ? pc : next_pc;
    assign retire      = !stall && !rst;

    always @(posedge clk) begin
        if (rst) pc <= 32'd0;
        else     pc <= pc_next_eff;
    end
endmodule