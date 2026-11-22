/* Memory map: code + data share one 16 KB image starting at 0.
   imem holds the code, dmem is preloaded with the same image so
   .rodata/.data are readable. Stack grows down from the top of dmem. */
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K }
ENTRY(_start)
SECTIONS {
    .text   : { *(.text.start) *(.text*) } > RAM
    .rodata : { *(.rodata*) *(.srodata*) } > RAM
    .data   : { *(.data*) *(.sdata*) } > RAM
    .bss    : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON); __bss_end = .; } > RAM
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
