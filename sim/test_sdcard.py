#!/usr/bin/env python3

import os
import shutil
import random
from pathlib import Path
from utils.utils import *
from models.sdcard_spi import SDCard

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge



@cocotb.test()
async def test_soc(dut):
    setup_file_logger(dut._log, "DEBUG")


    clk = dut.clk
    reset = dut.rst

    mem = {
        0xdeadbeef * 512: 0xa7
    }

    # init system
    sdcard = SDCard(dut, dut.sd_clk, dut.cs, dut.mosi, dut.miso, mem=mem)
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())

    cocotb.start_soon(log_sim_speed(dut, clk))

    dut.write_block.value = 0
    dut.read_block.value = 0
    reset.value = 1
    await ClockCycles(clk, 5)
    reset.value = 0
    await RisingEdge(clk)

    await ClockCycles(clk, 5)

    dut.block_addr.value = 0xdeadbeef
    dut.read_data.value = 0xdeadbeef
    dut.spi_wr_byte.value = 0x87
    # dut.write_block.value = 1
    # dut.read_block.value = 1
    dut.spi_send_byte.value = 1
    await RisingEdge(clk)
    dut.spi_send_byte.value = 0
    dut.write_block.value = 0
    dut.read_block.value = 0

    await ClockCycles(clk, 10000)





def test_runner():
    sim = get_runner("verilator")

    top_module = "sdcard_spi_phy"
    sim_dir = Path(__file__).parent
    rtl_dir = sim_dir.parent / "RTL"
    sources = list(rtl_dir.glob("**/*.sv")) # SV source files
    includes = [p.parent for p in list(set(rtl_dir.glob("**/*.svh")))] # SV header files
    includes += [rtl_dir]
    waivers = [str(w) for w in rtl_dir.glob("**/*.vlt")] # Verilator waivers for 3rd party IP


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
            "--threads", "2",
            "--public-flat-rw",
            "--timing",
            "--x-assign", "unique",
            "--x-initial", "unique",
            "--x-initial-edge"
        ],
    )

    sim.test(
        hdl_toplevel=top_module,
        test_module=Path(__file__).stem,
        waves=True,
        gui=True,
        test_args=[
            "+verilator+rand+reset+2",
            "+verilator+seed+1234",
        ],
    )

if __name__ == "__main__":
    test_runner()