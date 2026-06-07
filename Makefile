# FPGA build Makefile for tangnano20k (GW2A-18C)

SRC_DIR = RTL
SIM_DIR = ./sim/
BUILD_DIR = build/
SYNTH_DIR = synth/
SYNTH_OUT = $(BUILD_DIR)synth.json
SYNTH_REPORT = $(BUILD_DIR)synth_report.txt
PNR_OUT = $(BUILD_DIR)pnr.json
PNR_REPORT = $(BUILD_DIR)pnr_report.txt
BITSTREAM = $(BUILD_DIR)bitstream.fs
CST = $(SYNTH_DIR)tangnano20k.cst
SDC = $(SYNTH_DIR)timing.sdc

# Sources (all .sv files in RTL/ recursive)
SRC = $(shell find $(SRC_DIR) -type f -name '*.sv')

# Device and board settings
DEVICE = GW2AR-LV18QN88C8/I7
BOARD = tangnano20k
FAMILY = GW2A-18C

# OSS CAD Suite commands - each wrapped with environment source
YOSYS = source /opt/oss-cad-suite/environment && yosys
NEXTPNR = source /opt/oss-cad-suite/environment && nextpnr-himbaechel
GOWIN_PACK = source /opt/oss-cad-suite/environment && gowin_pack
OPENFPGALOADER = source /opt/oss-cad-suite/environment && openFPGALoader

# Firmware variables
FIRMWARE_DIR = firmware
BOOTLOADER_HEX = $(FIRMWARE_DIR)/bin/bootloader.hex
# Track all firmware C files, headers, assembly files, linker scripts, and makefile
FW_SRC = $(shell find $(FIRMWARE_DIR) -type f \( -name '*.[chS]' -o -name '*.ld' -o -name 'Makefile' \))


##################
### FPGA BUILD ###
##################

.PHONY: all clean flash flash_persist synth pnr asm

#---------------------------------------------------------------------
# Main build target
#---------------------------------------------------------------------
all: $(BITSTREAM)
	@echo "========================================"
	@echo "Build successful!"
	@echo "Bitstream: $(BITSTREAM)"
	@echo "========================================"

#---------------------------------------------------------------------
# Flash compiled bitstream to device
#---------------------------------------------------------------------
flash: $(BITSTREAM)
	@echo "========================================"
	@echo "Programming FPGA..."
	@echo "========================================"
	$(OPENFPGALOADER) -b $(BOARD) $(BITSTREAM)

#---------------------------------------------------------------------
# Flash compiled bitstream to device flash (persistent)
#---------------------------------------------------------------------
flash_persist: $(BITSTREAM)
	@echo "========================================"
	@echo "Programming FPGA Internal Flash..."
	@echo "========================================"
	$(OPENFPGALOADER) -b $(BOARD) -f $(BITSTREAM)

#---------------------------------------------------------------------
# Dependency chain
#---------------------------------------------------------------------

$(BUILD_DIR):
	@mkdir -p $@

# Synthesis
$(SYNTH_OUT): $(SRC) $(BOOTLOADER_HEX) | $(BUILD_DIR)
	@echo "========================================"
	@echo "Running synthesis..."
	@echo "========================================"
	$(YOSYS) -l $(SYNTH_REPORT) -m slang -p "\
        read_slang --top top --keep-hierarchy $(SRC); \
        hierarchy -check -top top; \
        synth_gowin -top top -abc9 -json $(SYNTH_OUT); \
    "
	@printf "\nSynthesis Warnings:\n"
	@grep -i "warning" $(SYNTH_REPORT) || true

#  Place & Route
$(PNR_OUT): $(SYNTH_OUT) $(CST) $(SDC)
	@echo "========================================"
	@echo "Running place & route..."
	@echo "========================================"
	$(NEXTPNR) --json $(SYNTH_OUT) --write $(PNR_OUT) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST) \
		--log $(PNR_REPORT) \
		--sdc $(SDC) \
		--seed=2473161942916117713
#-r
	@printf "\nPnR Warnings:\n"
	@grep -i "warning" $(PNR_REPORT) || true

# Bitstream generation
$(BITSTREAM): $(PNR_OUT)
	@echo "========================================"
	@echo "Compiling bitstream..."
	@echo "========================================"
	$(GOWIN_PACK) -d $(FAMILY) -o $(BITSTREAM) $(PNR_OUT)

# Aliases
synth: $(SYNTH_OUT)
pnr: $(PNR_OUT)
asm: $(BITSTREAM)


##################
#### Firmware ####
##################

$(BOOTLOADER_HEX): $(FW_SRC)
	@echo "========================================"
	@echo "Building Firmware..."
	@echo "========================================"
	$(MAKE) -C $(FIRMWARE_DIR)


##################
### SIMULATION ###
##################

.PHONY: sim waves

soc_sim: $(BOOTLOADER_HEX)
	cd $(SIM_DIR) && python3 test_soc.py

sd_sim:
	cd $(SIM_DIR) && python3 test_sdcard.py

soc_verify: $(BOOTLOADER_HEX)
	cd $(SIM_DIR) && python3 test_verify.py

soc_waves:
	@test -f $(SIM_DIR)sim_build/dump.fst || (echo "Error: dump.fst not found in $(SIM_DIR)sim_build/. Simulate a target first." && exit 1)
	surfer -s $(SIM_DIR)core_state.surf.ron $(SIM_DIR)sim_build/dump.fst

sd_waves:
	@test -f $(SIM_DIR)sim_build/dump.fst || (echo "Error: dump.fst not found in $(SIM_DIR)sim_build/. Simulate a target first." && exit 1)
	surfer -s $(SIM_DIR)sdcard_state.surf.ron $(SIM_DIR)sim_build/dump.fst

waves:
	@test -f $(SIM_DIR)sim_build/dump.fst || (echo "Error: dump.fst not found in $(SIM_DIR)sim_build/. Simulate a target first." && exit 1)
	surfer -s $(SIM_DIR)state.surf.ron $(SIM_DIR)sim_build/dump.fst


# Clean All
clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(FIRMWARE_DIR) clean
	rm -rf $(SIM_DIR)__pycache__
	rm -f $(SIM_DIR)results.xml
	rm -rf $(SIM_DIR)sim_build