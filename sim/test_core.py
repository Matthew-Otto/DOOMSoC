#!/usr/bin/env python3

import os
import random
from pathlib import Path
from utils.utils import *
from utils.spike_runner import *

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge

from cocotbext.axi import AxiMaster, AxiLiteMaster
from cocotbext.axi import AxiBus, AxiLiteBus, AxiLiteWriteBus, AxiLiteReadBus
from cocotbext.axi import AxiRam
from cocotbext.axi.sparse_memory import SparseMemory


tohost = 0x90000000
max_run_cycles = 1000

@cocotb.test()
async def test_core(dut):
    setup_file_logger(dut._log, "DEBUG")

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
        reset_active_high=True

        sys_clk_ns = round((1/329_400_000) * 1e12)
        mem_clk_ns = round((1/164_700_000) * 1e12)
        # init system
        # sdram = SDRAM(dut, busclk)
        cocotb.start_soon(Clock(clk, sys_clk_ns, unit="ps").start())
        cocotb.start_soon(Clock(busclk, mem_clk_ns, unit="ps").start())

        icache_bus = bind_pulp_axi(dut.axi_slv_ports)
        imem = AxiRam(icache_bus, busclk, reset, reset_active_level=reset_active_high, size=int(2**32))
        for addr,val in mem.items():
            imem.write(addr,[val])

        dmem = cocotb.start_soon(sim_data_mem(dut, busclk, mem))

        await reset_dut(clk, reset)
        

        await RisingEdge(clk)
        last_cycle_valid = False
        dut.cpu.regfile_i.regs[5].value = 0x80000000
        dut.cpu.regfile_i.regs[11].value = 0x00001020

        for cycle in range(max_run_cycles):
            await RisingEdge(clk)

        dmem.cancel()



def test_runner():
    sim = get_runner("verilator")

    top_module = "core_top"
    work_dir = Path(__file__).parent
    rtl_dir = work_dir.parent / "RTL"
    sources = list(rtl_dir.glob("**/*.sv"))
    includes = [p.parent for p in list(set(rtl_dir.glob("**/*.svh")))]
    includes += [rtl_dir]

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