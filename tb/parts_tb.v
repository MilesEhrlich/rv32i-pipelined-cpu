`timescale 1ns/1ps
module parts_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    integer errors = 0;

    task expect32(input [8*16-1:0] name, input [31:0] got, input [31:0] want);
        if (got !== want) begin
            $display("FAIL %0s: got %h, expected %h", name, got, want);
            errors = errors + 1;
        end
    endtask

    // Register file
    reg        rf_we = 0;
    reg [4:0]  rf_rs1, rf_rs2, rf_rd;
    reg [31:0] rf_wd;
    wire [31:0] rf_rd1, rf_rd2;
    regfile rf (.clk(clk), .we(rf_we), .rs1(rf_rs1), .rs2(rf_rs2), .rd(rf_rd),
                .wd(rf_wd), .rd1(rf_rd1), .rd2(rf_rd2));

    // Immediate generator
    reg  [31:0] ig_instr;
    wire [31:0] ig_imm;
    imm_gen ig (.instr(ig_instr), .imm(ig_imm));

    // ALU
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu (.a(a), .b(b), .op(op), .result(alu_y), .zero(alu_zero));

    task alu_check(input [8*16-1:0] name, input [3:0] t_op,
                   input [31:0] t_a, input [31:0] t_b, input [31:0] want);
        begin
            op = t_op; a = t_a; b = t_b; #1;
            expect32(name, alu_y, want);
        end
    endtask

    // Data memory
    reg        dm_we = 0;
    reg [2:0]  dm_f3;
    reg [31:0] dm_addr, dm_wd;
    wire [31:0] dm_rd;
    dmem dm (.clk(clk), .we(dm_we), .funct3(dm_f3), .addr(dm_addr),
             .wd(dm_wd), .rd(dm_rd));

    initial begin
        // Register file: write x5, try to write x0
        rf_rd = 5; rf_wd = 123; rf_we = 1; @(posedge clk); #1;
        rf_rd = 0; rf_wd = 99;             @(posedge clk); #1;
        rf_we = 0; rf_rs1 = 5; rf_rs2 = 0; #1;
        expect32("reg x5", rf_rd1, 123);
        expect32("reg x0", rf_rd2, 0);

        // Immediates (real encoded instructions)
        ig_instr = 32'hFFF00293; #1; expect32("imm I addi -1", ig_imm, 32'hFFFFFFFF);
        ig_instr = 32'h00512423; #1; expect32("imm S sw 8",    ig_imm, 32'd8);
        ig_instr = 32'hFE000EE3; #1; expect32("imm B beq -4",  ig_imm, 32'hFFFFFFFC);
        ig_instr = 32'h123452B7; #1; expect32("imm U lui",     ig_imm, 32'h12345000);
        ig_instr = 32'h008000EF; #1; expect32("imm J jal 8",   ig_imm, 32'd8);

        // ALU
        alu_check("add",  0, 5, 3, 8);
        alu_check("sub",  1, 3, 5, 32'hFFFFFFFE);
        alu_check("sll",  2, 1, 31, 32'h80000000);
        alu_check("slt",  3, 32'hFFFFFFFF, 1, 1);           // -1 < 1 signed
        alu_check("sltu", 4, 32'hFFFFFFFF, 1, 0);           // huge > 1 unsigned
        alu_check("xor",  5, 32'hFF00FF00, 32'h0FF00FF0, 32'hF0F0F0F0);
        alu_check("srl",  6, 32'hFFFFFFF0, 4, 32'h0FFFFFFF);
        alu_check("sra",  7, 32'hFFFFFFF0, 4, 32'hFFFFFFFF);
        alu_check("or",   8, 32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF);
        alu_check("and",  9, 32'hF0F0F0F0, 32'hFF00FF00, 32'hF000F000);

        // Data memory (synchronous: writes and reads happen on the rising edge)
        dm_addr = 0; dm_wd = 32'h11223344; dm_f3 = 3'b010; dm_we = 1;
        @(posedge clk); #1; dm_we = 0;
        dm_addr = 1; dm_f3 = 3'b000; @(posedge clk); #1; expect32("lb",  dm_rd, 32'h00000033);
        dm_addr = 3; dm_f3 = 3'b100; @(posedge clk); #1; expect32("lbu", dm_rd, 32'h00000011);

        dm_addr = 2; dm_wd = 32'h80; dm_f3 = 3'b000; dm_we = 1;   // sb
        @(posedge clk); #1; dm_we = 0;
        dm_addr = 2; dm_f3 = 3'b000; @(posedge clk); #1; expect32("lb neg", dm_rd, 32'hFFFFFF80);
        dm_addr = 0; dm_f3 = 3'b010; @(posedge clk); #1; expect32("lw",     dm_rd, 32'h11803344);
        dm_addr = 2; dm_f3 = 3'b001; @(posedge clk); #1; expect32("lh",     dm_rd, 32'h00001180);

        if (errors == 0) $display("All parts tests passed");
        else             $display("%0d errors", errors);
        $finish;
    end
endmodule