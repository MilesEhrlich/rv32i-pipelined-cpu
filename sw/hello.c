// First real C program on the CPU. Prints over MMIO and self-checks;
// main's return value becomes the exit code (0 = pass).
#include "mmio.h"

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

static void sort(int *a, int n) {           // insertion sort
    for (int i = 1; i < n; i++) {
        int k = a[i], j = i - 1;
        while (j >= 0 && a[j] > k) { a[j + 1] = a[j]; j--; }
        a[j + 1] = k;
    }
}

int data[8] = {42, -7, 19, 0, 1000, -300, 5, 19};
char message[] = "Hello from my RISC-V CPU!\n";

int main(void) {
    int fails = 0;
    uint32_t t0 = MMIO_CYCLES;

    puts_(message);

    puts_("fib(0..12):");
    for (int i = 0; i <= 12; i++) { putchar_(' '); print_int(fib(i)); }
    putchar_('\n');
    if (fib(12) != 144) fails++;

    sort(data, 8);
    puts_("sorted:");
    for (int i = 0; i < 8; i++) { putchar_(' '); print_int(data[i]); }
    putchar_('\n');
    for (int i = 1; i < 8; i++) if (data[i - 1] > data[i]) fails++;

    volatile int a = 1234, b = -56;          // volatile: force real mul/div at runtime
    puts_("1234 * -56 = "); print_int(a * b); putchar_('\n');
    puts_("1234 / -56 = "); print_int(a / b); putchar_('\n');
    puts_("1234 % -56 = "); print_int(a % b); putchar_('\n');
    if (a * b != -69104 || a / b != -22 || a % b != 2) fails++;

    puts_("cycles: "); print_uint(MMIO_CYCLES - t0); putchar_('\n');
    puts_(fails ? "SELF-CHECK FAILED\n" : "all self-checks passed\n");
    return fails;
}
