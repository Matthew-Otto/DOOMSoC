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

    benchmarks = os.path.join(os.getcwd(), "../../benchmarks/bin")

    test_files = [os.path.join(benchmarks,f) for f in os.listdir(benchmarks) if f.endswith(".hex") and os.path.isfile(os.path.join(benchmarks, f))]
    elf_files = [e.replace(".hex", ".elf") for e in test_files]

    assert test_files, "Error: compile a test program before running simulation"
    for e in elf_files:
        if not os.path.isfile(e):
            assert 0, f"Error: elf file {e} does not exist"

    for hex_f, elf_f in zip(test_files, elf_files):
        dut._log.info(f"Running test: {elf_f}")

        mem = parse_verilog_hex(hex_f)

        clk = dut.core_clk
        busclk = dut.bus_clk
        reset = dut.reset

        # init system
        sdram = SDRAM(dut.sdram_i.sdram_controller_i, busclk, mem=mem)
        sys_clk_ps = round((1/329_400_000) * 1e12)
        mem_clk_ps = round((1/164_700_000) * 1e12)
        cocotb.start_soon(Clock(clk, sys_clk_ps, unit="ps").start())
        cocotb.start_soon(Clock(busclk, mem_clk_ps, unit="ps").start())
    
        cocotb.start_soon(log_sim_speed(dut, clk))
        await reset_dut(clk, reset)

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