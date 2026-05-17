# Toolchain Definitions
PREFIX  = riscv64-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

BIN_DIR = bin
BUILD_DIR = build

# Architecture and Compiler Flags
ARCH    = -march=rv32im -mabi=ilp32
CFLAGS  = $(ARCH) -O0 -Wall -Wextra -ffreestanding -nostdlib -mstrict-align
LDSCRIPT = linker.ld
LDFLAGS = -T $(LDSCRIPT) -nostartfiles -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/bootloader.map

SRC = bootloader.c
OBJ = bootloader.o
ASM = $(BUILD_DIR)/bootloader.asm
ELF = $(BIN_DIR)/bootloader.elf
HEX = $(BIN_DIR)/bootloader.hex

# Extract the ROM base address from the linker script
ROM_BASE = $(shell awk '/ROM.*ORIGIN/ { match($$0, /0x[0-9a-fA-F]+/); print substr($$0, RSTART, RLENGTH) }' $(LDSCRIPT))


# Default target
all: $(ASM) $(HEX)

# Create build directory if not present
$(BIN_DIR):
	mkdir -p $(BIN_DIR)
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile and link into ELF
$(ELF): $(SRC) $(LDSCRIPT) | $(BIN_DIR) $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC) -o $@

# Convert ELF to Verilog hex
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 --adjust-vma=-$(ROM_BASE) $< $@

# Generate Disassembly
$(ASM): $(ELF)
	$(OBJDUMP) -d $< > $@

# Clean up build artifacts
clean:
	rm -rf bin/
	rm -rf build/

.PHONY: all clean