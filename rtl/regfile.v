// 32 x 32-bit register file, two read ports, one write port.
//
// PARITY=1 adds one even-parity bit per register, written with the data.
// perr1/perr2 flag a read whose data and parity disagree, i.e. a register
// that changed without being written (a bit flip). With PARITY=0 the parity
// bits and checkers are not built and perr1/perr2 are 0.
//
// With `define FI_PORTS (board fault injection, rtl/fi_top.v only) the file
// also takes injection commands; the caller must not flip while we=1, and
// only when fi_ready=1. The flipped value is built from a copy of the
// register taken the cycle before (fi_val), never from the RAM's own read
// output: on the FPGA the register file is LUT RAM, and writing back
// "read XOR mask" in one cycle sometimes undid the flip.
module regfile #(parameter PARITY = 0) (
    input  wire        clk,
    input  wire        we,          // write enable
    input  wire [4:0]  rs1, rs2, rd,
    input  wire [31:0] wd,          // write data
    output wire [31:0] rd1, rd2,    // read data
    output wire        perr1, perr2 // parity error on rd1 / rd2
`ifdef FI_PORTS
    ,
    input  wire        fi_clr,      // regs[fi_reg] = 0 (and its parity)
    input  wire        fi_flip,     // regs[fi_reg] ^= fi_mask, parity untouched
    input  wire        fi_par_flip, // par[fi_reg] ^= 1
    input  wire [4:0]  fi_reg,
    input  wire [31:0] fi_mask,
    output wire        fi_ready     // fi_val is the register's current value
`endif
);
    reg [31:0] regs [0:31];
    reg        par  [0:31];
    integer i;
`ifndef SYNTHESIS
    // Simulation only: start from zeros instead of X. Hardware doesn't need
    // it (x0 reads as 0 through the mux below; software initializes the rest)
    // and an ASIC has no way to preload flip-flops. A register never written
    // has unknown parity on hardware too, but software writes before reading.
    initial for (i = 0; i < 32; i = i + 1) begin regs[i] = 0; par[i] = 0; end
`endif

`ifdef FI_PORTS
    reg [31:0] fi_val;
    reg        fi_pval, fi_ok = 0;
    always @(posedge clk) begin
        fi_val  <= regs[fi_reg];
        fi_pval <= par[fi_reg];
        fi_ok   <= !fi_clr && !fi_flip && !fi_par_flip && !(we && rd == fi_reg);
    end
    assign fi_ready = fi_ok;
`endif

    always @(posedge clk)
`ifdef FI_PORTS
        if (fi_clr)       regs[fi_reg] <= 32'd0;
        else if (fi_flip) regs[fi_reg] <= fi_val ^ fi_mask;
        else
`endif
        if (we && rd != 0) regs[rd] <= wd;    // x0 is never written

    assign rd1 = (rs1 == 0) ? 32'd0 : regs[rs1];
    assign rd2 = (rs2 == 0) ? 32'd0 : regs[rs2];

    generate if (PARITY) begin : g_par
        always @(posedge clk)
`ifdef FI_PORTS
            if (fi_clr)           par[fi_reg] <= 1'b0;
            else if (fi_par_flip) par[fi_reg] <= ~fi_pval;
            else if (fi_flip)     ;
            else
`endif
            if (we && rd != 0) par[rd] <= ^wd;
        assign perr1 = (rs1 != 0) && (^regs[rs1] != par[rs1]);
        assign perr2 = (rs2 != 0) && (^regs[rs2] != par[rs2]);
    end else begin : g_nopar
        assign perr1 = 1'b0;
        assign perr2 = 1'b0;
    end endgenerate
endmodule
