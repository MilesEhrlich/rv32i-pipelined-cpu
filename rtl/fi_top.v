// Board fault injection: the pipelined core runs sw/digits.c on the Tang Nano
// 9K while this module flips one bit per trial, and reports every trial over
// the UART (fault/board_fi.py collects them).
//
// One trial:
//   1. pick an image (0..99), a target and a bit, uniformly like fi_sim.cpp:
//      register file  one of the 31x32 data bits (plus the 31 parity bits
//                     when PARITY=1), or the PC (one of 32 bits); targets
//                     alternate between trials
//   2. restore data memory from instruction memory (same image; the program
//      writes its stack and could have hit anything last trial), clear the
//      register file, hold the core in reset
//   3. golden run: no fault; record cycles, class, checksum
//   4. pick a cycle uniformly in [0, golden cycles), restore, run again and
//      flip the bit at that cycle (register flips wait for a cycle in which
//      the register file is not written and its copy of the target is fresh:
//      see regfile.v)
//   5. stop on exit, detection (parity rf_err or MMIO_FAULT), execution
//      outside .text (TEXT_END), or 3x the golden cycles; send a report
//
// Report, 37 bytes little-endian:
//   A5 5A | trial u16 | target u8 (0 reg, 1 pc, 2 parity) | reg u8 | bit u8 |
//   image u8 | fire cycle u32 (FFFFFFFF: never fired) | golden cycles u32 |
//   golden class u8 | golden checksum u32 | golden flags u8 | flags u8 |
//   exit code u8 | class u32 | checksum u32 | cycles u32 |
//   sum u8 (of the 36 bytes before it; the host drops reports that fail it)
// flags: 0 exited, 1 class reported, 2 checksum reported, 3 MMIO_FAULT,
//        4 parity error, 5 left .text, 6 timeout
module fi_top #(
    parameter PROGRAM      = "",
    parameter MEM_WORDS    = 4096,
    parameter PARITY       = 0,
    parameter [31:0] TEXT_END = 32'hFFFF_FFFF,
    parameter [31:0] SEED  = 32'h2545_F491,
    parameter CLKS_PER_BIT = 234               // 27 MHz / 115200
) (
    input  wire       clk,
    input  wire [1:0] btn,
    output wire [5:0] led,
    output wire       uart_tx
);
    localparam AW = $clog2(MEM_WORDS);
    localparam [31:0] MAGIC = 32'hFA17_DE7C;
    localparam [9:0]  NSLOTS = PARITY ? 10'd1023 : 10'd992;   // 31*33 or 31*32
    localparam T_REG = 2'd0, T_PC = 2'd1, T_PAR = 2'd2;

    // ------------------------------------------------------------ reset
    reg [7:0] por = 0;
    wire rst = !por[7];
    always @(posedge clk) if (!por[7]) por <= por + 1'b1;

    // ------------------------------------------------------------ random
    reg [31:0] rng = SEED;                         // xorshift32, steps every cycle
    wire [31:0] r1 = rng ^ (rng << 13);
    wire [31:0] r2 = r1 ^ (r1 >> 17);
    wire [31:0] rng_next = r2 ^ (r2 << 5);
    always @(posedge clk) rng <= rng_next;

    // ------------------------------------------------------------ core + memories
    reg         core_rst = 1;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata, pc;
    wire        dmem_we, mmio_we, mmio_re, retire, rf_err, dbg_ex_valid, dbg_rf_we, dbg_fi_ready;
    wire [3:0]  dmem_be;
    wire [31:0] mmio_addr, mmio_wdata, dbg_ex_pc;
    reg  [31:0] mmio_rdata;
    wire        fi_pc_flip, fi_rf_flip, fi_par_flip, fi_rf_clr;
    wire [4:0]  fi_reg;
    wire [31:0] fi_mask;

    cpu_core #(.PARITY(PARITY)) u_core (
        .clk(clk), .rst(core_rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_we(dmem_we), .dmem_be(dmem_be),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .retire(retire), .pc(pc), .rf_err(rf_err),
        .fi_pc_flip(fi_pc_flip), .fi_rf_flip(fi_rf_flip), .fi_par_flip(fi_par_flip),
        .fi_rf_clr(fi_rf_clr), .fi_reg(fi_reg), .fi_mask(fi_mask),
        .dbg_ex_valid(dbg_ex_valid), .dbg_ex_pc(dbg_ex_pc), .dbg_rf_we(dbg_rf_we),
        .dbg_fi_ready(dbg_fi_ready));

    // restore: read imem word i, write it to dmem word i-1 one cycle later
    reg            restoring = 0;
    reg  [AW:0]    rcnt = 0;
    reg  [AW-1:0]  wr_idx;
    reg            wr_en = 0;
    wire [31:0] im_addr = restoring ? {{(30-AW){1'b0}}, rcnt[AW-1:0], 2'b00} : imem_addr;
    imem #(.WORDS(MEM_WORDS), .FILE(PROGRAM)) u_imem (
        .clk(clk), .addr(im_addr), .instr(imem_rdata));
    bram_be #(.WORDS(MEM_WORDS)) u_dmem (
        .clk(clk),
        .addr (wr_en ? {{(30-AW){1'b0}}, wr_idx, 2'b00} : dmem_addr),
        .we   (wr_en ? 1'b1 : dmem_we),
        .be   (wr_en ? 4'hF : dmem_be),
        .wdata(wr_en ? imem_rdata : dmem_wdata),
        .rdata(dmem_rdata));

    // ------------------------------------------------------------ trial FSM
    localparam S_PICK_IMG = 4'd0, S_PICK_BIT = 4'd1, S_RESTORE = 4'd2, S_SETTLE = 4'd3,
               S_RUN = 4'd4, S_PICK_CYC = 4'd5, S_REPORT = 4'd6, S_WAIT = 4'd7;
    reg [3:0]  state = S_WAIT;
    reg        faulty;                 // this run injects
    reg [1:0]  tgt_kind = T_REG;
    reg [1:0]  tgt;
    reg [4:0]  t_reg, t_bit;
    reg [6:0]  image;
    reg [15:0] trial = 0;
    reg [31:0] cyc, limit, inj, fire_cyc;
    reg        fired;
    reg [2:0]  settle;
    // results of the current run
    reg        exited, got_res, got_chk, det_sw, det_hw, wildf, timeout;
    reg [7:0]  exit_code;
    reg [31:0] result, check;
    // golden run
    reg [31:0] g_cycles, g_check;
    reg [7:0]  g_class, g_flags;

    wire fire = state == S_RUN && faulty && !fired && cyc >= inj &&
                (tgt == T_PC || (!dbg_rf_we && dbg_fi_ready));
    assign fi_pc_flip  = fire && tgt == T_PC;
    assign fi_rf_flip  = fire && tgt == T_REG;
    assign fi_par_flip = fire && tgt == T_PAR;
    assign fi_rf_clr   = restoring && rcnt < 32;
    assign fi_reg      = fi_rf_clr ? rcnt[4:0] : t_reg;
    assign fi_mask     = 32'd1 << t_bit;

    always @(*) case (mmio_addr)
        32'h1000_0008: mmio_rdata = cyc;
        32'h1000_0020: mmio_rdata = {25'd0, image};
        default:       mmio_rdata = 32'd0;     // UART never busy, buttons 0
    endcase

    wire w_exit  = mmio_we && mmio_addr == 32'h1000_0004;
    wire w_res   = mmio_we && mmio_addr == 32'h1000_0024;
    wire w_chk   = mmio_we && mmio_addr == 32'h1000_0028;
    wire w_fault = mmio_we && mmio_addr == 32'h1000_002C && mmio_wdata == MAGIC;
    wire wild    = dbg_ex_valid && dbg_ex_pc >= TEXT_END;
    wire stop    = w_exit || w_fault || rf_err || wild || cyc + 1 >= limit;
    wire [7:0] flags = {1'b0, timeout, wildf, det_hw, det_sw, got_chk, got_res, exited};

    // report shift register
    reg  [287:0] pkt;
    reg  [5:0]   nbytes;
    reg  [7:0]   psum;
    reg          tx_start = 0, tx_wait = 0;
    wire         tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .start(tx_start), .data(nbytes == 1 ? psum : pkt[7:0]), .tx(uart_tx), .busy(tx_busy));

    task begin_restore; begin
        restoring <= 1; rcnt <= 0; wr_en <= 0; core_rst <= 1; state <= S_RESTORE;
    end endtask

    always @(posedge clk) begin
        tx_start <= 0;
        if (rst) begin
            state <= S_WAIT; core_rst <= 1; restoring <= 0; wr_en <= 0;
        end else case (state)
        S_WAIT: state <= S_PICK_IMG;               // (after power-on reset)

        // ---- pick image and bit by rejection sampling (uniform) ----
        S_PICK_IMG: if (rng[6:0] < 7'd100) begin
            image <= rng[6:0]; state <= S_PICK_BIT;
        end
        S_PICK_BIT: if (tgt_kind == T_PC) begin
            tgt <= T_PC; t_reg <= 0; t_bit <= rng[4:0]; state <= S_RESTORE; faulty <= 0;
            begin_restore;
        end else if (rng[9:0] < NSLOTS) begin
            if (rng[9:0] < 10'd992) begin
                tgt <= T_REG; t_reg <= rng[9:5] + 5'd1; t_bit <= rng[4:0];
            end else begin
                tgt <= T_PAR; t_reg <= rng[9:0] - 10'd991; t_bit <= 0;
            end
            faulty <= 0;
            begin_restore;
        end

        // ---- restore dmem, clear registers ----
        S_RESTORE: begin
            rcnt   <= rcnt + 1'b1;
            wr_en  <= 1; wr_idx <= rcnt[AW-1:0];
            if (rcnt == MEM_WORDS) begin
                restoring <= 0; wr_en <= 0; settle <= 0; state <= S_SETTLE;
            end
        end
        S_SETTLE: begin                            // 4 reset cycles fetching from 0, like fi_sim
            settle <= settle + 1'b1;
            if (settle == 3) begin
                core_rst <= 0; cyc <= 0; fired <= 0; fire_cyc <= 32'hFFFF_FFFF;
                exited <= 0; got_res <= 0; got_chk <= 0; det_sw <= 0; det_hw <= 0;
                wildf <= 0; timeout <= 0; exit_code <= 0; result <= 32'hFFFF_FFFF; check <= 0;
                limit <= faulty ? 3 * g_cycles : 32'd1 << 21;
                state <= S_RUN;
            end
        end

        // ---- run ----
        S_RUN: begin
            cyc <= cyc + 1'b1;
            if (fire) begin fired <= 1; fire_cyc <= cyc; end
            if (w_res) begin result <= mmio_wdata; got_res <= 1; end
            if (w_chk) begin check  <= mmio_wdata; got_chk <= 1; end
            if (w_exit) begin exited <= 1; exit_code <= mmio_wdata[7:0]; end
            if (w_fault) det_sw <= 1;
            if (rf_err)  det_hw <= 1;
            if (wild)    wildf  <= 1;
            if (stop) begin
                core_rst <= 1;
                if (!(w_exit || w_fault || rf_err || wild)) timeout <= 1;
                state <= faulty ? S_REPORT : S_PICK_CYC;
                if (!faulty) begin
                    g_cycles <= cyc + 1'b1;
                    g_class  <= w_res ? mmio_wdata[7:0] : result[7:0];
                    g_check  <= w_chk ? mmio_wdata : check;
                end
            end
        end
        S_PICK_CYC: begin                          // flags of the golden run are final now
            g_flags <= flags;
            if ({15'd0, rng[16:0]} < g_cycles) begin
                inj <= {15'd0, rng[16:0]}; faulty <= 1; begin_restore;
            end else if (g_cycles > 32'd131072 || !exited) begin
                inj <= 0; faulty <= 1; begin_restore;   // golden run failed: report it
            end
        end

        // ---- report ----
        S_REPORT: if (!tx_wait) begin
            pkt <= {cyc, check, result, exit_code, flags, g_flags, g_check, g_class, g_cycles,
                    fire_cyc, 1'b0, image, 3'b0, t_bit, 3'b0, t_reg, 6'b0, tgt, trial,
                    8'h5A, 8'hA5};
            nbytes <= 37; psum <= 0; tx_wait <= 1;
        end else if (nbytes == 0) begin
            tx_wait <= 0; trial <= trial + 1'b1;
            tgt_kind <= (tgt_kind == T_PC) ? T_REG : T_PC;
            state <= S_PICK_IMG;
        end else if (!tx_busy && !tx_start) begin
            tx_start <= 1;
        end else if (tx_start) begin
            pkt <= pkt >> 8; nbytes <= nbytes - 1'b1; psum <= psum + pkt[7:0];
        end
        default: state <= S_WAIT;
        endcase
    end

    assign led = ~trial[11:6];                     // LEDs are active low
endmodule
