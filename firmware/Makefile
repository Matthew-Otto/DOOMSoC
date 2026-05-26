# Toolchain Definitions
PREFIX  = riscv64-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

BIN_DIR = bin
BUILD_DIR = build

# Architecture and Compiler Flags
ARCH    = -march=rv32i_zmmul -mabi=ilp32
CFLAGS  = $(ARCH) -O2 -Wall -Wextra -ffreestanding -nolibc -mstrict-align
LDSCRIPT = linker.ld
LDFLAGS = -T $(LDSCRIPT) -nostartfiles -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/bootloader.map

SRC = bootloader.c
ASM = $(BUILD_DIR)/bootloader.s
OBJ = bootloader.o
DISASM = $(BUILD_DIR)/bootloader.asm
ELF = $(BIN_DIR)/bootloader.elf
HEX = $(BIN_DIR)/bootloader.hex

# Extract the ROM base address from the linker script
ROM_BASE = $(shell awk '/ROM.*ORIGIN/ { match($$0, /0x[0-9a-fA-F]+/); print substr($$0, RSTART, RLENGTH) }' $(LDSCRIPT))


# Default target
all: $(ASM) $(HEX) $(DISASM)

# Create directories
$(BIN_DIR) $(BUILD_DIR):
	mkdir -p $@

# Compile program to ASM
$(ASM): $(SRC) | $(BIN_DIR) $(BUILD_DIR)
	$(CC) $(CFLAGS) -S $< -o $@

# Compile and link into ELF
$(ELF): $(ASM) $(LDSCRIPT)
	$(CC) $(CFLAGS) $(LDFLAGS) $< -o $@

# Convert ELF to Verilog hex
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 --adjust-vma=-$(ROM_BASE) $< $@

# Generate Disassembly
$(DISASM): $(ELF)
	$(OBJDUMP) -d $< > $@

# Clean up build artifacts
clean:
	rm -rf bin/
	rm -rf build/

.PHONY: all clean