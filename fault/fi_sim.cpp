// Single-bit fault injection into the pipelined RV32I core (cpu_core.v)
// while it runs the int8 digit classifier (sw/digits.c).
//
// Verilator compiles cpu_core; this file provides synchronous instruction and
// data memories (one-cycle read latency, like the FPGA block RAMs), the MMIO
// devices digits.c uses, and the fault injector.
//
// Each trial: reset, pick an image, pick a cycle uniformly inside that
// image's fault-free run, pick a bit uniformly inside the target structure,
// flip it once, run to completion, classify the outcome:
//   masked     identical logits (checksum) and class
//   tolerated  logits changed, class unchanged
//   sdc        silent data corruption: wrong class, normal exit
//   crash      no usable output: hang (no exit within 3x the fault-free
//              cycles), non-zero exit, an instruction from outside the
//              program's code executed, or the result/checksum never reported
//   detected   the hardened build caught the fault and stopped: register
//              parity error (rf_err) or the model checksum (MMIO_FAULT)
//
// Usage: fi_sim key=value ...
//   hex=sw/build/digits.hex  text_end=0x...   (end of .text, from the ELF)
//   target=<structure>       trials=N  seed=S
//   region=start:len[,start:len]  (for target=dmem / imem: byte ranges to hit)
//   at=start                 inject at cycle 0 (persistent memory faults)
//   golden=1                 run every image once without faults
//   parity=1                 the core was built with PARITY=1: the regfile
//                            target also includes the 31 parity bits
// Output: one CSV line per trial on stdout.
#include "Vcpu_core.h"
#include "Vcpu_core___024root.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <random>
#include <string>
#include <vector>

static const uint32_t MEM_WORDS = 4096;            // 16 KB, matches link.ld
static const int      N_TEST    = 100;

struct Golden { uint32_t cls, sum, cycles; };

// ---------------------------------------------------------------- simulator
struct Sim {
    Vcpu_core* top = nullptr;
    std::vector<uint32_t> image, imem, dmem;
    uint32_t text_end = 0, cycle = 0;
    // MMIO state
    uint32_t image_sel = 0, result = 0xFFFFFFFF, check = 0, exit_code = 0;
    bool exited = false, wild = false, got_result = false, got_check = false, detected = false;

    explicit Sim(const std::vector<uint32_t>& img, uint32_t te) : image(img), text_end(te) {
        top = new Vcpu_core;
    }
    ~Sim() { delete top; }

    void reset(uint32_t img_sel) {
        imem = image; imem.resize(MEM_WORDS, 0);
        dmem = image; dmem.resize(MEM_WORDS, 0);
        image_sel = img_sel; result = 0xFFFFFFFF; check = 0; exit_code = 0;
        exited = false; wild = false; got_result = false; got_check = false; detected = false; cycle = 0;
        auto* r = top->rootp;
        for (int i = 0; i < 32; i++) { r->cpu_core__DOT__u_rf__DOT__regs[i] = 0; r->cpu_core__DOT__u_rf__DOT__par[i] = 0; }
        top->rst = 1; top->imem_rdata = 0; top->dmem_rdata = 0; top->mmio_rdata = 0;
        for (int i = 0; i < 3; i++) step(true);
        top->rst = 0;
        cycle = 0;
    }

    uint32_t mmio_read(uint32_t a) {
        switch (a) {
            case 0x10000008: return cycle;
            case 0x10000020: return image_sel;
            default:         return 0;          // UART never busy, etc.
        }
    }

    void step(bool in_reset = false) {
        top->clk = 0; top->eval();
        top->mmio_rdata = mmio_read(top->mmio_addr); top->eval();
        uint32_t ia = top->imem_addr, da = top->dmem_addr;
        bool we = top->dmem_we; uint32_t be = top->dmem_be, wd = top->dmem_wdata;
        if (!in_reset && top->mmio_we) {
            switch (top->mmio_addr) {
                case 0x10000004: exited = true; exit_code = top->mmio_wdata; break;
                case 0x10000024: result = top->mmio_wdata; got_result = true; break;
                case 0x10000028: check  = top->mmio_wdata; got_check = true; break;
                case 0x1000002C:                 // MMIO_FAULT, only with the magic value:
                    if (top->mmio_wdata == 0xFA17DE7Cu) detected = true;   // a flipped s3 can
                    break;                       // redirect the result write here
                default: break;                  // UART output etc.: ignored
            }
        }
        top->clk = 1; top->eval();               // registers sample old memory outputs
        uint32_t iw = ia >> 2, dw = da >> 2;
        uint32_t inew = iw < MEM_WORDS ? imem[iw] : 0;
        uint32_t dnew = dw < MEM_WORDS ? dmem[dw] : 0;
        if (we && dw < MEM_WORDS) {
            uint32_t m = 0;
            for (int k = 0; k < 4; k++) if (be >> k & 1) m |= 0xFFu << (8 * k);
            dmem[dw] = (dmem[dw] & ~m) | (wd & m);
        }
        top->imem_rdata = inew; top->dmem_rdata = dnew; top->eval();
        if (!in_reset) {
            auto* r = top->rootp;
            if (r->cpu_core__DOT__ex_valid && r->cpu_core__DOT__ex_pc >= text_end) wild = true;
            if (top->rf_err) detected = true;      // fail-stop on parity error
            cycle++;
        }
    }

    // run until exit, wild execution, or cycle limit
    void run(uint32_t limit) {
        while (!exited && !wild && !detected && cycle < limit) step();
    }
};

// ----------------------------------------------------------- fault sites
// A structure is a list of (name, flip function) per bit.
struct Bit { std::string site; int bit; };
using Flipper = void (*)(Sim&, const Bit&);

template <typename T> static void xor_bit(T& v, int b) { v ^= (T)((T)1 << b); }

struct Field { const char* name; int width; };

static void flip_named(Sim& s, const Bit& b) {
    auto* r = s.top->rootp;
    const std::string& n = b.site;
#define F(sig) if (n == #sig) { xor_bit(r->cpu_core__DOT__##sig, b.bit); return; }
    F(pc_D)
    F(ex_valid) F(ex_reg_we) F(ex_load) F(ex_store) F(ex_br) F(ex_jal) F(ex_jalr) F(ex_b_imm)
    F(ex_a_sel) F(ex_alu_op) F(ex_f3) F(ex_rd) F(ex_pc) F(ex_imm) F(ex_rs1_val) F(ex_rs2_val)
    F(ex_fm1) F(ex_fw1) F(ex_fm2) F(ex_fw2)
    F(mem_valid) F(mem_reg_we) F(mem_load) F(mem_store) F(mem_mmio) F(mem_f3) F(mem_rd)
    F(mem_result) F(mem_wdata)
    F(wb_we) F(wb_rd) F(wb_val)
#undef F
    if (n.rfind("x", 0) == 0) {                     // x1..x31
        int reg = atoi(n.c_str() + 1);
        xor_bit(r->cpu_core__DOT__u_rf__DOT__regs[reg], b.bit);
        return;
    }
    if (n.rfind("p", 0) == 0 && n.size() <= 3) {    // p1..p31: parity bits
        int reg = atoi(n.c_str() + 1);
        r->cpu_core__DOT__u_rf__DOT__par[reg] ^= 1;
        return;
    }
    if (n == "instr") { xor_bit(s.top->imem_rdata, b.bit); s.top->eval(); return; }
    if (n == "ldata") { xor_bit(s.top->dmem_rdata, b.bit); s.top->eval(); return; }
    if (n.rfind("dmem@", 0) == 0 || n.rfind("imem@", 0) == 0) {
        uint32_t addr = strtoul(n.c_str() + 5, nullptr, 0);
        auto& mem = n[0] == 'd' ? s.dmem : s.imem;
        uint32_t w = addr >> 2, sh = (addr & 3) * 8 + b.bit;
        if (w < MEM_WORDS) mem[w] ^= 1u << sh;
        return;
    }
    fprintf(stderr, "unknown site %s\n", n.c_str()); exit(2);
}

static bool g_parity = false;

static std::vector<Field> fields_for(const std::string& t) {
    if (t == "pc")     return {{"pc_D", 32}};
    if (t == "id_ex")  return {{"ex_valid",1},{"ex_reg_we",1},{"ex_load",1},{"ex_store",1},{"ex_br",1},
                               {"ex_jal",1},{"ex_jalr",1},{"ex_b_imm",1},{"ex_a_sel",2},{"ex_alu_op",4},
                               {"ex_f3",3},{"ex_rd",5},{"ex_pc",32},{"ex_imm",32},{"ex_rs1_val",32},
                               {"ex_rs2_val",32},{"ex_fm1",1},{"ex_fw1",1},{"ex_fm2",1},{"ex_fw2",1}};
    if (t == "ex_mem") return {{"mem_valid",1},{"mem_reg_we",1},{"mem_load",1},{"mem_store",1},
                               {"mem_mmio",1},{"mem_f3",3},{"mem_rd",5},{"mem_result",32},{"mem_wdata",32}};
    if (t == "mem_wb") return {{"wb_we",1},{"wb_rd",5},{"wb_val",32}};
    if (t == "regfile") { static std::vector<std::string> names; static std::vector<Field> f;
        if (f.empty()) { for (int i = 1; i < 32; i++) names.push_back("x" + std::to_string(i));
                         if (g_parity) for (int i = 1; i < 32; i++) names.push_back("p" + std::to_string(i));
                         for (auto& nm : names) f.push_back({nm.c_str(), nm[0] == 'p' ? 1 : 32}); }
        return f; }
    if (t == "instr")  return {{"instr", 32}};
    if (t == "ldata")  return {{"ldata", 32}};
    return {};
}

// ------------------------------------------------------------------ main
static std::vector<uint32_t> load_hex(const char* path) {
    std::vector<uint32_t> w; std::ifstream f(path); std::string line;
    while (std::getline(f, line)) if (!line.empty()) w.push_back(strtoul(line.c_str(), nullptr, 16));
    return w;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::map<std::string, std::string> a;
    for (int i = 1; i < argc; i++) {
        std::string s = argv[i]; auto eq = s.find('=');
        if (eq != std::string::npos) a[s.substr(0, eq)] = s.substr(eq + 1);
    }
    auto get = [&](const char* k, const char* d) { return a.count(k) ? a[k] : std::string(d); };
    auto img = load_hex(get("hex", "sw/build/digits.hex").c_str());
    uint32_t text_end = strtoul(get("text_end", "0").c_str(), nullptr, 0);
    Sim sim(img, text_end ? text_end : 0xFFFFFFFF);
    g_parity = get("parity", "0") == "1";

    // fault-free reference for every image
    std::vector<Golden> gold(N_TEST);
    for (int n = 0; n < N_TEST; n++) {
        sim.reset(n); sim.run(5'000'000);
        if (!sim.exited || sim.exit_code || sim.wild || sim.detected) { fprintf(stderr, "golden run %d failed\n", n); return 1; }
        gold[n] = {sim.result, sim.check, sim.cycle};
    }
    if (get("golden", "0") == "1") {
        printf("image,class,checksum,cycles\n");
        for (int n = 0; n < N_TEST; n++) printf("%d,%u,%08x,%u\n", n, gold[n].cls, gold[n].sum, gold[n].cycles);
        return 0;
    }

    std::string target = get("target", "regfile");
    int trials = atoi(get("trials", "100").c_str());
    std::mt19937_64 rng(strtoull(get("seed", "1").c_str(), nullptr, 0));

    // enumerate the target's bits
    std::vector<Bit> bits;
    if (target == "dmem" || target == "imem") {
        // region=start:len[,start:len...]  (several byte ranges, uniformly over all bits)
        std::string regs = get("region", "");
        size_t pos = 0;
        while (pos < regs.size()) {
            size_t end = regs.find(',', pos); if (end == std::string::npos) end = regs.size();
            std::string reg = regs.substr(pos, end - pos);
            auto c = reg.find(':');
            uint32_t start = strtoul(reg.substr(0, c).c_str(), nullptr, 0);
            uint32_t len = strtoul(reg.substr(c + 1).c_str(), nullptr, 0);
            for (uint32_t b = 0; b < len; b++) {
                char nm[32]; snprintf(nm, sizeof nm, "%s@0x%x", target.c_str(), start + b);
                for (int k = 0; k < 8; k++) bits.push_back({nm, k});
            }
            pos = end + 1;
        }
    } else {
        for (auto& f : fields_for(target))
            for (int k = 0; k < f.width; k++) bits.push_back({f.name, k});
    }
    if (bits.empty()) { fprintf(stderr, "no bits for target %s\n", target.c_str()); return 2; }

    printf("target,site,bit,image,cycle,outcome,cycles_run\n");
    for (int t = 0; t < trials; t++) {
        int n = rng() % N_TEST;
        const Bit& b = bits[rng() % bits.size()];
        uint32_t when = get("at", "random") == "start" ? 0 : (uint32_t)(rng() % gold[n].cycles);
        sim.reset(n);
        sim.run(when);
        if (!sim.exited && !sim.wild) flip_named(sim, b);
        sim.run(3 * gold[n].cycles);
        const char* out;
        if (sim.detected)                               out = "detected";
        else if (sim.wild || !sim.exited || sim.exit_code || !sim.got_result || !sim.got_check) out = "crash";
        else if (sim.result != gold[n].cls)            out = "sdc";
        else if (sim.check != gold[n].sum)              out = "tolerated";
        else                                            out = "masked";
        printf("%s,%s,%d,%d,%u,%s,%u\n", target.c_str(), b.site.c_str(), b.bit, n, when, out, sim.cycle);
    }
    return 0;
}
