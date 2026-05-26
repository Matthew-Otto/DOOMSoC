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


async def valid_instr(dut, clk):
    # find first instr that is valid and not stall
    await ReadOnly()
    while True:
        if dut.cpu.branch_unit.valid.value != 1:
            await RisingEdge(dut.cpu.branch_unit.valid)
            await ReadOnly()
        if dut.cpu.stall_EX.value == 1:
            await FallingEdge(dut.cpu.stall_EX)
            await ReadOnly()
        if dut.cpu.branch_unit.valid.value and not dut.cpu.stall_EX.value:
            break


def sim_regs(dut):
    regs = [int(r.value) for r in dut.cpu.regfile_i.regs]
    return regs[::-1]


@cocotb.test()
async def test_verify(dut):
    setup_file_logger(dut._log, "INFO")

    firmware_dir = os.path.join(os.getcwd(), "../../firmware/bin")
    bootloader = os.path.join(firmware_dir, "bootloader.elf")

    if not os.path.isfile(bootloader):
        assert 0, f"Error: bootloader file {bootloader} does not exist"

    ref_sim = SpikeRunner(bootloader)


    dut._log.info(f"Executing Bootloader")

    clk = dut.sys_clk
    pclk = dut.p_clk
    reset = dut.sys_clk_rst

    # init system
    sdram = SDRAM(dut.sdram_i.sdram_controller_i, clk)
    sys_clk_ps = round((1/81_000_000) * 1e12)
    p_clk_ps = round((1/81_000_000) * 1e12) #39.682
    cocotb.start_soon(Clock(clk, sys_clk_ps, unit="ps").start())
    cocotb.start_soon(Clock(pclk, p_clk_ps, unit="ps").start())

    cocotb.start_soon(log_sim_speed(dut, clk))
    dut.btn1_db.value = 0
    dut.sys_pll_lock.value = 1
    dut.sclk_pll_lock.value = 1
    await FallingEdge(reset)

    tracing = True
    iters = 1000000
    step = 10000

    # await ClockCycles(clk, 50000)
    # return
    # await ClockCycles(busclk, 1)
    # dut.btn1_db.value = 1
    # await ClockCycles(clk, 1)
    # dut.btn1_db.value = 0

    instr_cnt = 0

    for _ in range(0,iters,step):
        if tracing:
            trace = ref_sim.stepn(step)

            if not trace:
                tracing = False

            for instr in trace:
                await valid_instr(dut, clk)
                instr_cnt += 1

                ref_pc, ref_instr, ref_asm = instr
                sim_pc = dut.cpu.branch_unit.PC.value

                print(f"{instr_cnt} Ref: {ref_pc} | {ref_instr} | {ref_asm}")
                print(f"{instr_cnt} Sim: {hex(sim_pc)}")

                if int(ref_pc,16) != sim_pc:
                    instr, regs = ref_sim.get_state_at(instr_cnt-1)
                    ref_pc, ref_instr, ref_asm = instr

                    print(f"Ref: {ref_pc} | {ref_instr} | {ref_asm}")
                    print(f"Ref regs:\n{regs}")

                    await ClockCycles(clk, 5)
                    assert 0, f"Error: PC mismatch at time {get_sim_time(unit='ps')}ps"

                await ClockCycles(clk, 1)

            # compare regfile
            ref_sim.dump_regfile()
            ref = ref_sim.regfile
            sim = sim_regs(dut)
            sim.insert(0,0)

            # BOZO
            ref[5] = 0

            diffs = []
            for i in range(len(sim)):
                if ref[i] != sim[i]:
                    diffs.append(i)
            if len(diffs) > 1:
                print("Spike:")
                print(ref_sim.format_regs(ref))
                print("RTL:")
                print(ref_sim.format_regs(sim))
                await ClockCycles(clk, 5)
                assert 0, f"Error: regfile does not match reference sim in registers: {diffs}"

        else:
            for _ in range(step):
                await valid_instr(dut, clk)
                await ClockCycles(clk, 1)

    #await ClockCycles(clk, 100000)
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
            "+verilator+seed+5",
        ],
    )

if __name__ == "__main__":
    test_runner()