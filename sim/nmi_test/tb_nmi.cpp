// Pruefstand nur fuer den CPU-Kern: geht ein NMI verloren, wenn er waehrend
// der Annahme eines IRQ kommt?
//
// Die CPU laeuft nativ in einer Schleife, IRQ liegt dauerhaft an und der
// Handler ist nur RTI - die CPU nimmt also staendig IRQs an. Fuer jeden
// Versatz k (in CPU-Takten) kommt der NMI k Takte spaeter, 16 Takte lang
// (wie bei BOTE: 100 Systemtakte). Gezaehlt wird, ob die CPU den
// NMI-Vektor $FFEA holt.
//
//   make && ./obj_dir/tb_nmi
#include "VP65C816.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static uint8_t mem[65536];
static VP65C816* cpu;
static int nmi_geholt;

static void takt() {                    // ein CPU-Takt = 3 Systemtakte, CE im dritten
    for (int c = 0; c < 3; c++) {
        cpu->CE = (c == 2);
        cpu->CLK = 0;
        cpu->eval();
        uint16_t a = cpu->A_OUT & 0xFFFF;
        cpu->D_IN = mem[a];
        cpu->eval();
        if (cpu->CE && cpu->RST_N) {
            if (!cpu->WE && cpu->VDA) mem[a] = cpu->D_OUT;          // WE ist aktiv low
            if (cpu->WE && (cpu->VDA || cpu->VPA) && a == 0xFFEA) nmi_geholt++;
        }
        cpu->CLK = 1;
        cpu->eval();
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    cpu = new VP65C816;
    int verloren = 0, versuche = 0;
    for (int k = 0; k < 40; k++) {
        memset(mem, 0xEA, sizeof mem);
        const uint8_t start[] = {0x18, 0xFB, 0x58, 0xEA, 0x80, 0xFD};   // CLC XCE CLI / NOP BRA
        memcpy(mem + 0x0200, start, sizeof start);
        mem[0x0300] = 0x40;                                            // IRQ: RTI
        mem[0x0400] = 0x80; mem[0x0401] = 0xFE;                        // NMI: BRA *
        mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x02;                        // RESET (emuliert)
        mem[0xFFEE] = 0x00; mem[0xFFEF] = 0x03;                        // IRQ nativ
        mem[0xFFEA] = 0x00; mem[0xFFEB] = 0x04;                        // NMI nativ
        cpu->RDY_IN = 1; cpu->ABORT_N = 1; cpu->IRQ_N = 1; cpu->NMI_N = 1;
        cpu->RST_N = 0;
        for (int i = 0; i < 10; i++) takt();
        cpu->RST_N = 1;
        for (int i = 0; i < 300; i++) takt();
        cpu->IRQ_N = 0;                                                // IRQ-Sturm
        for (int i = 0; i < 100 + k; i++) takt();
        nmi_geholt = 0;
        cpu->NMI_N = 0;
        for (int i = 0; i < 16; i++) takt();
        cpu->NMI_N = 1;
        for (int i = 0; i < 300; i++) takt();
        versuche++;
        if (!nmi_geholt) { verloren++; printf("Versatz %2d: NMI verloren\n", k); }
    }
    printf("%d von %d NMIs verloren\n", verloren, versuche);
    delete cpu;
    return verloren ? 1 : 0;
}
