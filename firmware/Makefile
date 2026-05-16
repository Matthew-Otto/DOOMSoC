# Toolchain Definitions
PREFIX  = riscv64-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

BIN_DIR = bin
BUILD_DIR = build

# Architecture and Compiler Flags
ARCH    = -march=rv32im -mabi=ilp32
CFLAGS  = $(ARCH) -O2 -Wall -Wextra -ffreestanding -nostdlib -mstrict-align
LDFLAGS = -T linker.ld -nostartfiles -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/bootloader.map

SRC = bootloader.c
OBJ = bootloader.o
ELF = $(BUILD_DIR)/bootloader.elf
ASM = $(BUILD_DIR)/bootloader.asm
HEX = $(BIN_DIR)/bootloader.hex

# Default target
all: $(ASM) $(HEX)

# Create build directory if not present
$(BIN_DIR):
	mkdir -p $(BIN_DIR)
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile and link into ELF
$(ELF): $(SRC) linker.ld | $(BIN_DIR) $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC) -o $@

# Convert ELF to Verilog hex
$(HEX): $(ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

# Generate Disassembly
$(ASM): $(ELF)
	$(OBJDUMP) -d $< > $@

# Clean up build artifacts
clean:
	rm -rf bin/
	rm -rf build/

.PHONY: all clean