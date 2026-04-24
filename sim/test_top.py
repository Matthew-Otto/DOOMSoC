#!/usr/bin/env python3

import random
from functools import partial
from pathlib import Path
from asyncio import Event

from models.utils import setup_file_logger, reset_dut
from models.sdram import SDRAM

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge
from cocotb.queue import Queue
from cocotbext.axi import AxiMaster, AxiLiteMaster
from cocotbext.axi import AxiBus, AxiLiteBus, AxiLiteWriteBus, AxiLiteReadBus
from cocotbext.axi import AxiRam



@cocotb.test()
async def test(dut):
    setup_file_logger(dut._log, "DEBUG")

    clk = dut.sys_clk
    memclk = dut.sdram_clk
    reset = dut.main_reset

    sys_clk_ns = round((1/329_400_000) * 1e12)
    mem_clk_ns = round((1/164_700_000) * 1e12)

    # init system
    sdram = SDRAM(dut, memclk)
    cocotb.start_soon(Clock(clk, sys_clk_ns, unit="ps").start())
    cocotb.start_soon(Clock(memclk, mem_clk_ns, unit="ps").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)


    dut.btn1_db.value = 1
    await ClockCycles(clk, 1)
    dut.btn1_db.value = 0

    dut.btn2_db.value = 1
    await ClockCycles(memclk, 10)
    dut.btn2_db.value = 0
    
    
    while dut.mt_state.value != 0:
        await ClockCycles(memclk, 100)

    sdram.dump(0x0, 0x100)







def test_runner():
    sim = get_runner("verilator")

    top_module = "top"
    work_dir = Path(__file__).parent
    rtl_dir = work_dir.parent / "RTL"
    sources = list(rtl_dir.glob("**/*.sv"))
    includes = [p.parent for p in list(rtl_dir.glob("**/*.svh"))]

    sim.build(
        sources=sources,
        includes=includes,
        hdl_toplevel=top_module,
        always=False,
        waves=True,
        build_args=[
            "-Wno-SELRANGE",
            "-Wno-WIDTH",
            "--trace-fst",
            "--trace-structs",
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