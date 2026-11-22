// 5-stage pipelined RV32I CPU: IF -> ID -> EX -> MEM -> WB
//
//   IF   next-PC mux drives the instruction block RAM; its output register
//        is the IF/ID boundary (instr_D), paired with pc_D.
//   ID   decode, register read (with WB->ID bypass), hazard detection
//   EX   ALU, branch/jump resolution, data-memory address (block RAM
//        latches it, so load data appears in MEM)
//   MEM  load byte/half extraction, memory-mapped I/O
//   WB   register write
//
// Hazards
//   data     forwarding into EX from MEM (ALU results only) and WB. A load
//            followed directly by a user of its result stalls 1 cycle and
//            gets the data from WB. (Forwarding load data straight out of
//            MEM also works and needs no stall, but puts block RAM -> byte
//            extract -> forward -> branch -> fetch in one cycle: 28.7 MHz.)
//            Forwarding selects are computed in ID and registered.
//   control  predict not-taken; a taken branch/jump is resolved in EX and
//            redirects fetch in the same cycle, squashing the 1 instruction
//            behind it (1-cycle penalty)
//
// PARITY=1 adds a parity bit to every register (see regfile.v). rf_err
// pulses when an instruction in EX used a register value whose parity was
// wrong when it was read in ID; the system should stop the CPU (fail-stop).
// Values taken from the WB bypass or the forwarding paths did not come from
// the register file and are not checked.
//
// Memories are outside the core (cpu_pipe.v wraps it with FPGA block RAM;
// an ASIC build connects SRAM macros). Both ports expect a SYNCHRONOUS
// memory: data is returned the cycle after the address is presented.
module cpu_core #(parameter PARITY = 0) (
    input  wire        clk,
    input  wire        rst,
    // instruction memory
    output wire [31:0] imem_addr,     // byte address of the next fetch
    input  wire [31:0] imem_rdata,    // instruction at last cycle's imem_addr
    // data memory
    output wire [31:0] dmem_addr,     // byte address (word = dmem_addr[31:2])
    output wire        dmem_we,
    output reg  [3:0]  dmem_be,       // byte enables for stores
    output reg  [31:0] dmem_wdata,    // store data, already aligned to its lanes
    input  wire [31:0] dmem_rdata,    // word at last cycle's dmem_addr
    // memory-mapped I/O (addresses 0x1xxxxxxx), driven from MEM
    output wire        mmio_we,
    output wire        mmio_re,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    input  wire [31:0] mmio_rdata,
    output reg         retire,        // 1 for each instruction completing WB
    output wire [31:0] pc,            // PC of the instruction in ID (debug)
    output wire        rf_err         // register-file parity error (PARITY=1)
);
    localparam OP_R      = 7'b0110011, OP_I     = 7'b0010011,
               OP_LOAD   = 7'b0000011, OP_STORE = 7'b0100011,
               OP_BRANCH = 7'b1100011, OP_JAL   = 7'b1101111,
               OP_JALR   = 7'b1100111, OP_LUI   = 7'b0110111,
               OP_AUIPC  = 7'b0010111;
    localparam A_RS1 = 2'd0, A_PC = 2'd1, A_ZERO = 2'd2;

    // Signals produced by later stages but needed earlier (feedback paths)
    wire        stall;          // ID: load-use hazard, hold IF and ID
    wire        redirect;       // EX: taken branch/jump
    wire [31:0] redirect_pc;
    reg         wb_we;          // MEM/WB register
    reg  [4:0]  wb_rd;
    reg  [31:0] wb_val;
    reg         mem_valid, mem_reg_we, mem_load, mem_store, mem_mmio;   // EX/MEM register
    reg  [2:0]  mem_f3;
    reg  [4:0]  mem_rd;
    reg  [31:0] mem_result, mem_wdata;
    wire [31:0] mem_val;        // MEM stage's final value (ALU result or load data)

    // =====================================================================
    // IF
    // =====================================================================
    reg  [31:0] pc_D;
    wire [31:0] instr_D = imem_rdata;
    wire [31:0] fetch_pc = rst      ? 32'd0 :
                           redirect ? redirect_pc :
                           stall    ? pc_D :          // re-fetch: hold ID
                                      pc_D + 32'd4;
    assign imem_addr = fetch_pc;
    always @(posedge clk) pc_D <= fetch_pc;
    assign pc = pc_D;

    // =====================================================================
    // ID
    // =====================================================================
    wire [6:0] opcode = instr_D[6:0];
    wire [4:0] rd_D   = instr_D[11:7];
    wire [2:0] f3_D   = instr_D[14:12];
    wire [4:0] rs1_D  = instr_D[19:15];
    wire [4:0] rs2_D  = instr_D[24:20];
    wire       f7_5   = instr_D[30];

    wire is_op    = opcode == OP_R,      is_opimm = opcode == OP_I;
    wire is_load  = opcode == OP_LOAD,   is_store = opcode == OP_STORE;
    wire is_br    = opcode == OP_BRANCH, is_jal   = opcode == OP_JAL;
    wire is_jalr  = opcode == OP_JALR,   is_lui   = opcode == OP_LUI;
    wire is_auipc = opcode == OP_AUIPC;

    wire reg_we_D  = is_op | is_opimm | is_load | is_jal | is_jalr | is_lui | is_auipc;
    wire uses_rs1  = is_op | is_opimm | is_load | is_store | is_br | is_jalr;
    wire uses_rs2  = is_op | is_store | is_br;

    reg [3:0] alu_op_D;
    always @(*) begin
        if (is_op || is_opimm) begin
            case (f3_D)
                3'b000:  alu_op_D = (is_op && f7_5) ? 4'd1 : 4'd0;  // sub : add
                3'b001:  alu_op_D = 4'd2;                           // sll
                3'b010:  alu_op_D = 4'd3;                           // slt
                3'b011:  alu_op_D = 4'd4;                           // sltu
                3'b100:  alu_op_D = 4'd5;                           // xor
                3'b101:  alu_op_D = f7_5 ? 4'd7 : 4'd6;             // sra : srl
                3'b110:  alu_op_D = 4'd8;                           // or
                default: alu_op_D = 4'd9;                           // and
            endcase
        end else alu_op_D = 4'd0;                                   // add
    end
    wire [1:0] a_sel_D = is_lui ? A_ZERO : (is_auipc | is_jal) ? A_PC : A_RS1;

    wire [31:0] imm_D;
    imm_gen u_imm (.instr(instr_D), .imm(imm_D));

    wire [31:0] rf1, rf2;
    wire        rf_perr1, rf_perr2;
    regfile #(.PARITY(PARITY)) u_rf (.clk(clk), .we(wb_we), .rs1(rs1_D), .rs2(rs2_D),
                  .rd(wb_rd), .wd(wb_val), .rd1(rf1), .rd2(rf2),
                  .perr1(rf_perr1), .perr2(rf_perr2));
    // WB -> ID bypass: a register written this cycle is read in the same cycle
    wire byp1_D = wb_we && wb_rd != 0 && wb_rd == rs1_D;
    wire byp2_D = wb_we && wb_rd != 0 && wb_rd == rs2_D;
    wire [31:0] rs1_val_D = byp1_D ? wb_val : rf1;
    wire [31:0] rs2_val_D = byp2_D ? wb_val : rf2;

    // ---- ID/EX register ----
    reg        ex_valid, ex_reg_we, ex_load, ex_store, ex_br, ex_jal, ex_jalr, ex_b_imm;
    reg [1:0]  ex_a_sel;
    reg [3:0]  ex_alu_op;
    reg [2:0]  ex_f3;
    reg [4:0]  ex_rd;
    reg [31:0] ex_pc, ex_imm, ex_rs1_val, ex_rs2_val;
    reg        ex_fm1, ex_fw1, ex_fm2, ex_fw2;   // forwarding selects, decided in ID
    reg        ex_perr;                          // used a register with bad parity

    // Load-use hazard: a load's data is not forwardable until it reaches WB
    assign stall = ex_valid && ex_load && ex_rd != 0 &&
                   ((uses_rs1 && rs1_D == ex_rd) || (uses_rs2 && rs2_D == ex_rd));

    // Forwarding is decided one stage early (in ID) and registered, keeping
    // the register-number comparators off the EX critical path. Next cycle,
    // the instruction now in EX will be in MEM, and the one in MEM in WB.
    wire fm1_D = ex_reg_we  && ex_rd  != 0 && ex_rd  == rs1_D;
    wire fw1_D = mem_reg_we && mem_rd != 0 && mem_rd == rs1_D;
    wire fm2_D = ex_reg_we  && ex_rd  != 0 && ex_rd  == rs2_D;
    wire fw2_D = mem_reg_we && mem_rd != 0 && mem_rd == rs2_D;

    // Parity: only flag values this instruction really takes from the file
    wire perr_D = (uses_rs1 && rf_perr1 && !byp1_D && !fm1_D && !fw1_D) ||
                  (uses_rs2 && rf_perr2 && !byp2_D && !fm2_D && !fw2_D);

    always @(posedge clk) begin
        if (rst || stall || redirect) begin          // insert a bubble
            ex_valid <= 0; ex_reg_we <= 0; ex_load <= 0; ex_store <= 0;
            ex_br <= 0; ex_jal <= 0; ex_jalr <= 0;
        end else begin
            ex_valid <= 1;     ex_reg_we <= reg_we_D;
            ex_load  <= is_load; ex_store <= is_store;
            ex_br    <= is_br;   ex_jal   <= is_jal;  ex_jalr <= is_jalr;
        end
        ex_b_imm   <= !is_op;  ex_a_sel <= a_sel_D;  ex_alu_op <= alu_op_D;
        ex_f3      <= f3_D;    ex_rd    <= rd_D;
        ex_pc      <= pc_D;    ex_imm   <= imm_D;
        ex_rs1_val <= rs1_val_D; ex_rs2_val <= rs2_val_D;
        ex_fm1 <= uses_rs1 && fm1_D;  ex_fw1 <= uses_rs1 && fw1_D;
        ex_fm2 <= uses_rs2 && fm2_D;  ex_fw2 <= uses_rs2 && fw2_D;
        ex_perr <= perr_D;
    end
    assign rf_err = ex_valid && ex_perr;       // bubbles never report

    // =====================================================================
    // EX
    // =====================================================================

    // Forwarding (selects precomputed in ID): newest value wins, MEM before WB.
    // Only registered values are forwarded (never load data out of MEM).
    wire [31:0] rs1_fwd = ex_fm1 ? mem_result : ex_fw1 ? wb_val : ex_rs1_val;
    wire [31:0] rs2_fwd = ex_fm2 ? mem_result : ex_fw2 ? wb_val : ex_rs2_val;

    wire [31:0] alu_a = ex_a_sel == A_PC ? ex_pc : ex_a_sel == A_ZERO ? 32'd0 : rs1_fwd;
    wire [31:0] alu_b = ex_b_imm ? ex_imm : rs2_fwd;
    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu (.a(alu_a), .b(alu_b), .op(ex_alu_op), .result(alu_y), .zero(alu_zero));

    reg take;
    always @(*) begin
        case (ex_f3)
            3'b000:  take = (rs1_fwd == rs2_fwd);
            3'b001:  take = (rs1_fwd != rs2_fwd);
            3'b100:  take = ($signed(rs1_fwd) <  $signed(rs2_fwd));
            3'b101:  take = ($signed(rs1_fwd) >= $signed(rs2_fwd));
            3'b110:  take = (rs1_fwd <  rs2_fwd);
            3'b111:  take = (rs1_fwd >= rs2_fwd);
            default: take = 1'b0;
        endcase
    end
    // Dedicated adders keep the ALU's operation mux off the address and
    // branch paths: ea = rs1 + imm (load/store address, jalr target),
    // pc_target = pc + imm (branch and jal target).
    wire [31:0] ea        = rs1_fwd + ex_imm;
    wire [31:0] pc_target = ex_pc + ex_imm;
    assign redirect    = ex_valid && (ex_jal || ex_jalr || (ex_br && take));
    assign redirect_pc = ex_jalr ? {ea[31:1], 1'b0} : pc_target;

    wire [31:0] ex_result = (ex_jal || ex_jalr) ? ex_pc + 32'd4 : alu_y;
    wire        ex_mmio   = (ea[31:28] == 4'h1);

    // Data memory: address/data presented in EX, the memory registers them.
    assign dmem_addr = ea;
    assign dmem_we   = ex_valid && ex_store && !ex_mmio;
    always @(*) begin
        case (ex_f3[1:0])
            2'b00:   begin dmem_be = 4'b0001 << ea[1:0];              dmem_wdata = {4{rs2_fwd[7:0]}};  end // sb
            2'b01:   begin dmem_be = ea[1] ? 4'b1100 : 4'b0011;       dmem_wdata = {2{rs2_fwd[15:0]}}; end // sh
            default: begin dmem_be = 4'b1111;                         dmem_wdata = rs2_fwd;            end // sw
        endcase
    end
    wire [31:0] dmem_word = dmem_rdata;

    always @(posedge clk) begin
        if (rst) begin
            mem_valid <= 0; mem_reg_we <= 0; mem_load <= 0; mem_store <= 0;
        end else begin
            mem_valid  <= ex_valid;
            mem_reg_we <= ex_valid && ex_reg_we;
            mem_load   <= ex_valid && ex_load;
            mem_store  <= ex_valid && ex_store;
        end
        mem_mmio   <= ex_mmio;
        mem_f3     <= ex_f3;
        mem_rd     <= ex_rd;
        mem_result <= (ex_load || ex_store) ? ea : ex_result;
        mem_wdata  <= rs2_fwd;
    end

    // =====================================================================
    // MEM
    // =====================================================================
    assign mmio_we    = mem_store && mem_mmio;
    assign mmio_re    = mem_load  && mem_mmio;
    assign mmio_addr  = mem_result;
    assign mmio_wdata = mem_wdata;

    wire [31:0] raw     = mem_mmio ? mmio_rdata : dmem_word;
    wire [31:0] shifted = raw >> {mem_result[1:0], 3'b000};
    reg  [31:0] load_val;
    always @(*) begin
        case (mem_f3)
            3'b000:  load_val = {{24{shifted[7]}},  shifted[7:0]};    // lb
            3'b001:  load_val = {{16{shifted[15]}}, shifted[15:0]};   // lh
            3'b100:  load_val = {24'd0, shifted[7:0]};                // lbu
            3'b101:  load_val = {16'd0, shifted[15:0]};               // lhu
            default: load_val = raw;                                  // lw
        endcase
    end
    assign mem_val = mem_load ? load_val : mem_result;

    // =====================================================================
    // WB  (MEM/WB register; the register file writes at the end of WB)
    // =====================================================================
    always @(posedge clk) begin
        wb_we  <= !rst && mem_reg_we;
        wb_rd  <= mem_rd;
        wb_val <= mem_val;
        retire <= !rst && mem_valid;
    end
endmodule
