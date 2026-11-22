# Build a C program into a $readmemh hex image for the CPU.
#   make            -> build/hello.hex
#   make PROG=foo   -> build/foo.hex from foo.c
#   make PROG=foo OUT=foo_x DEFS="-DX"  -> build/foo_x.hex, foo.c built with -DX
LLVM   ?= /opt/homebrew/opt/llvm/bin
LLD    ?= /opt/homebrew/opt/lld/bin
CC      = $(LLVM)/clang
OBJCOPY = $(LLVM)/llvm-objcopy
OBJDUMP = $(LLVM)/llvm-objdump
PROG   ?= hello
OUT    ?= $(PROG)
DEFS   ?=

CFLAGS  = --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 -O2 \
          -ffreestanding -fno-builtin -nostdlib -mno-relax -Wall
LDFLAGS = -fuse-ld=$(LLD)/ld.lld -T link.ld -Wl,--gc-sections

all: build/$(OUT).hex

build/$(OUT).elf: crt0.S runtime.c $(PROG).c mmio.h link.ld $(wildcard ml_model.h) | build
	$(CC) $(CFLAGS) $(DEFS) $(LDFLAGS) -ffunction-sections -o $@ crt0.S runtime.c $(PROG).c

build/$(OUT).hex: build/$(OUT).elf bin2hex.py
	$(OBJCOPY) -O binary $< build/$(OUT).bin
	python3 bin2hex.py build/$(OUT).bin $@
	$(OBJDUMP) -d $< > build/$(OUT).dis
	@echo "$@: $$(wc -l < $@) words"

build:
	mkdir -p build

clean:
	rm -r build
.PHONY: all clean
