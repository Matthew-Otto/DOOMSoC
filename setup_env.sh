#!/usr/bin/env bash

OSS_CAD_SUITE_PATH="/opt/oss-cad-suite/environment"
LOCAL_LIBS="$PWD/.python-libs"

if [ -f "$OSS_CAD_SUITE_PATH" ]; then
    echo "[-] Sourcing OSS CAD Suite from $OSS_CAD_SUITE_PATH."
    source "$OSS_CAD_SUITE_PATH"
else
    echo "[!] Error: Could not find OSS CAD Suite at $OSS_CAD_SUITE_PATH"
    return 1 2>/dev/null || exit 1
fi

if [ ! -d "$LOCAL_LIBS" ]; then
    echo "[-] venv is broken with the oss-cad-suite provided Python."
    echo "[-] Installing dependencies into local directory ($LOCAL_LIBS)"
    python3 -m pip install -U pip
    python3 -m pip install --target="$LOCAL_LIBS" cocotb cocotbext-axi pexpect
else
    echo "[-] Dependencies already installed in $LOCAL_LIBS. Skipping pip."
fi

echo "[-] Activating local environment variables."
export PYTHONPATH="$LOCAL_LIBS:$PYTHONPATH"
# Ensure binaries like cocotb-config are accessible
export PATH="$LOCAL_LIBS/bin:$PATH"

echo "=================================================="
echo "SUCCESS: Environment is set up"
echo -e "$(python3 --version)\n$(which python3)"
echo -e "cocotb\n$(which cocotb-config)"
echo -e "$(verilator --version)\n$(which verilator)"
echo -e "$(yosys --version)\n$(which yosys)"
echo -e "$(nextpnr-himbaechel --version)$(which nextpnr-himbaechel)"
echo -e "$(openFPGALoader --version)\n$(which openFPGALoader)"
echo -e "$(surfer --version)\n$(which surfer)"
echo "=================================================="