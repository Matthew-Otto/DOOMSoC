# Toolchain prefix
RISCV_PREFIX = riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc
AS      = $(RISCV_PREFIX)as
LD      = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump

ARCH = rv32im
ABI  = ilp32

SRC_DIR = ./src
BIN_DIR = bin

LINKER_SCRIPT = spike.ld
CRT0 = crt0.S

CFLAGS = -march=$(ARCH) -mabi=$(ABI) -Wall -O2 -nostdlib -ffreestanding -lgcc
ASFLAGS = -march=$(ARCH) -mabi=$(ABI)
LDFLAGS = -T $(LINKER_SCRIPT) -nostdlib -nostartfiles


# Get all C source files
C_SRCS = $(wildcard $(SRC_DIR)/*.c)
# Derive object and output names
OBJS = $(C_SRCS:$(SRC_DIR)/%.c=$(BIN_DIR)/%.o)
ELFS = $(C_SRCS:$(SRC_DIR)/%.c=$(BIN_DIR)/%.elf)
HEX = $(C_SRCS:$(SRC_DIR)/%.c=$(BIN_DIR)/%.hex)
LST = $(C_SRCS:$(SRC_DIR)/%.c=$(BIN_DIR)/%.lst)


# Default target
all: $(ELFS) $(HEX) $(LST)

# Create build directory if not present
$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# Compile C files
$(BIN_DIR)/%.o: $(SRC_DIR)/%.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble crt0
$(BIN_DIR)/crt0.o: $(CRT0) | $(BIN_DIR)
	$(CC) $(ASFLAGS) -c $< -o $@

# Link into ELF
$(BIN_DIR)/%.elf: $(BIN_DIR)/%.o $(BIN_DIR)/crt0.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Convert ELF to Verilog hex
$(BIN_DIR)/%.hex: $(BIN_DIR)/%.elf
	$(OBJCOPY) -O verilog $< $@

# generate readable disassembly
$(BIN_DIR)/%.lst: $(BIN_DIR)/%.elf
	$(OBJDUMP) -D $< > $@


# Clean up
clean:
	rm -rf build
	rm -rf bin
	rm -f *.o *.elf *.bin *.asm

.PHONY: all clean
