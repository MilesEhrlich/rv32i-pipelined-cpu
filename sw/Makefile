# Build a C program into a $readmemh hex image for the CPU.
#   make            -> build/hello.hex
#   make PROG=foo   -> build/foo.hex from foo.c
LLVM   ?= /opt/homebrew/opt/llvm/bin
LLD    ?= /opt/homebrew/opt/lld/bin
CC      = $(LLVM)/clang
OBJCOPY = $(LLVM)/llvm-objcopy
OBJDUMP = $(LLVM)/llvm-objdump
PROG   ?= hello

CFLAGS  = --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 -O2 \
          -ffreestanding -fno-builtin -nostdlib -mno-relax -Wall
LDFLAGS = -fuse-ld=$(LLD)/ld.lld -T link.ld -Wl,--gc-sections

all: build/$(PROG).hex

build/$(PROG).elf: crt0.S runtime.c $(PROG).c mmio.h link.ld | build
	$(CC) $(CFLAGS) $(LDFLAGS) -ffunction-sections -o $@ crt0.S runtime.c $(PROG).c

build/$(PROG).hex: build/$(PROG).elf bin2hex.py
	$(OBJCOPY) -O binary $< build/$(PROG).bin
	python3 bin2hex.py build/$(PROG).bin $@
	$(OBJDUMP) -d $< > build/$(PROG).dis
	@echo "$@: $$(wc -l < $@) words"

build:
	mkdir -p build

clean:
	rm -r build
.PHONY: all clean
