#!/usr/bin/env python3

import os
import shutil
import random
from pathlib import Path
from utils.utils import *
from utils.spike_runner import *
from models.sdram import SDRAM

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge



@cocotb.test()
async def test_soc(dut):
    setup_file_logger(dut._log, "INFO")

    # firmware_dir = os.path.join(os.getcwd(), "../../firmware/bin")
    # bootloader = os.path.join(firmware_dir, "/bootloader.hex")

    # if not os.path.isfile(bootloader):
    #     assert 0, f"Error: bootloader file {bootloader} does not exist"

    # mem = parse_verilog_hex(bootloader)

    dut._log.info(f"Running test")

    mem = None

    clk = dut.core_clk
    busclk = dut.bus_clk
    pclk = dut.p_clk
    reset = dut.async_reset

    # init system
    sdram = SDRAM(dut.sdram_i.sdram_controller_i, busclk, mem=mem)
    sys_clk_ps = round((1/80_000_000) * 1e12)
    bus_clk_ps = round((1/160_000_000) * 1e12)
    cocotb.start_soon(Clock(clk, sys_clk_ps, unit="ps").start())
    cocotb.start_soon(Clock(busclk, bus_clk_ps, unit="ps").start())
    cocotb.start_soon(Clock(pclk, 39.682, unit="ns").start())

    cocotb.start_soon(log_sim_speed(dut, clk))

    await ClockCycles(clk, 100000)

    #sdram.dump(0x0, 0x100)





def test_runner():
    sim = get_runner("verilator")

    top_module = "top"
    sim_dir = Path(__file__).parent
    firmware_dir = sim_dir.parent / "firmware"
    build_dir = sim_dir / "sim_build"
    rtl_dir = sim_dir.parent / "RTL"
    sources = list(rtl_dir.glob("**/*.sv")) # SV source files
    includes = [p.parent for p in list(set(rtl_dir.glob("**/*.svh")))] # SV header files
    includes += [rtl_dir]
    waivers = [str(w) for w in rtl_dir.glob("**/*.vlt")] # Verilator waivers for 3rd party IP

    hex_path = str(firmware_dir / "bin" / "bootloader.hex")

    # Copy firmware to sim directory
    build_dir.mkdir(parents=True, exist_ok=True)
    for mem_file in firmware_dir.glob("*.mem"):
        shutil.copy(mem_file, build_dir)

    sim.build(
        sources=sources,
        includes=includes,
        hdl_toplevel=top_module,
        always=False,
        waves=True,
        parameters={
            "BOOT_ROM_FILE": f'"{hex_path}"'
        },
        build_args=[
            "--build", "-j", "12", # Parallelize Compilation
            *waivers,
            "-Wno-SELRANGE",
            "-Wno-WIDTH",
            "--trace-fst",
            "--trace-structs",
            "--threads", "4",
        ],
    )

    sim.test(
        hdl_toplevel=top_module,
        test_module=Path(__file__).stem,
        waves=True,
        gui=True
    )

if __name__ == "__main__":
    test_runner()