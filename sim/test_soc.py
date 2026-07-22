#!/usr/bin/env python3

import os
import shutil
import random
from pathlib import Path
from utils.utils import *
from utils.spike_runner import *
from models.sdram import SDRAM
from models.sdcard_spi import SDCard

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge



@cocotb.test()
async def test_soc(dut):
    setup_file_logger(dut._log, "DEBUG")

    dut._log.info(f"Executing Bootloader")

    clk = dut.sys_clk
    pclk = dut.p_clk
    sd_clk = dut.sdcard_clk
    reset = dut.sys_clk_rst

    mem = {
        0xdeadbeef * 512: 0xa7
    }

    # init system
    sdram = SDRAM(dut.sdram_i.sdram_controller_i, clk)
    sdcard = SDCard(dut,
        clk=dut.sd_clk,
        cs=dut.sdcard_i.sdcard_spi_phy_i.cs,
        mosi=dut.sdcard_i.sdcard_spi_phy_i.mosi,
        miso=dut.sdcard_i.spi_miso,
        mem=mem
    )
    sys_clk_ps = round((1/81_000_000) * 1e12)
    p_clk_ps = round((1/81_000_000) * 1e12) #39.682 ns
    cocotb.start_soon(Clock(clk, sys_clk_ps, unit="ps").start())
    cocotb.start_soon(Clock(sd_clk, sys_clk_ps*4, unit="ps").start())
    cocotb.start_soon(Clock(pclk, p_clk_ps, unit="ps").start())

    cocotb.start_soon(log_sim_speed(dut, clk))
    dut.btn1_db.value = 0
    dut.sys_pll_lock.value = 1
    dut.sclk_pll_lock.value = 1
    await FallingEdge(reset)

    await ClockCycles(clk, 300000)
    await ClockCycles(clk, 10)





def test_runner():
    sim = get_runner("verilator")

    top_module = "top"
    sim_dir = Path(__file__).parent
    firmware_dir = sim_dir.parent / "firmware"
    rtl_dir = sim_dir.parent / "RTL"
    sources = list(rtl_dir.glob("**/*.sv")) # SV source files
    includes = [p.parent for p in list(set(rtl_dir.glob("**/*.svh")))] # SV header files
    includes += [rtl_dir]
    waivers = [str(w) for w in rtl_dir.glob("**/*.vlt")] # Verilator waivers for 3rd party IP

    hex_path = str(firmware_dir / "bin" / "bootloader.hex")

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
            "+verilator+seed+12345",
        ],
    )

if __name__ == "__main__":
    test_runner()