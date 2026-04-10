# FPGA build Makefile for tangnano20k (GW2A-18C)

FMAX = 100
SRC_DIR = RTL
BUILD_DIR = build/
SYNTH_OUT = $(BUILD_DIR)synth.json
SYNTH_REPORT = $(BUILD_DIR)synth_report.txt
PNR_OUT = $(BUILD_DIR)pnr.json
PNR_REPORT = $(BUILD_DIR)pnr_report.txt
BITSTREAM = $(BUILD_DIR)bitstream.fs
CST = tangnano20k.cst
SDC = timing.sdc

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
$(SYNTH_OUT): $(SRC) | $(BUILD_DIR)
	@echo "========================================"
	@echo "Running synthesis..."
	@echo "========================================"
	$(YOSYS) -l $(SYNTH_REPORT) -p "read_verilog -sv $(SRC); synth_gowin -top top -json $(SYNTH_OUT)"
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
		--sdc $(SDC) \
		--log $(PNR_REPORT)
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

#---------------------------------------------------------------------
# Clean targets
#---------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
