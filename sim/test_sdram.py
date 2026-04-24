#!/usr/bin/env python3

import random
from functools import partial
from pathlib import Path
from asyncio import Event

from models.sdram import SDRAM

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge
from cocotb.queue import Queue
from cocotbext.axi import AxiMaster, AxiLiteMaster
from cocotbext.axi import AxiBus, AxiLiteBus, AxiLiteWriteBus, AxiLiteReadBus
from cocotbext.axi import AxiRam

async def reset_dut(clk, rst, active_low=False):
    await RisingEdge(clk)
    rst.value = not active_low
    await ClockCycles(clk, 5)
    rst.value = active_low
    await ClockCycles(clk, 5)
    print("DUT reset")


async def write_burst(dut, clk, addr, data):
    """initiates a burst, terminates early if len(data) < burst_len"""
    dut.write.value = 1
    dut.addr.value = addr
    dut.write_strb.value = 0xf
    dut.write_data.value = data[0]

    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)

    for idx,val in enumerate(data[1::]):
        dut.write_data.value = val
        dut.stop.value = (idx == len(data)-2)
        await RisingEdge(clk)
    dut.write.value = 0
    dut.stop.value = 0



async def capture_reads(dut, clk, stop_event, read_data, addr_queue):
    while not stop_event.is_set():
        await RisingEdge(clk)
        if dut.read_data_val.value:
            addr = await addr_queue.get()
            read_data[addr] = dut.read_data.value


@cocotb.test()
async def basic_mem_controller_test(dut):
    dut._log.setLevel("DEBUG")

    clk = dut.mem_clk
    reset = dut.reset

    # init system
    sdram = SDRAM(dut, clk)
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)

    test_data = {}

    for addr in [0, 16, 32, 64]:
        data = [random.getrandbits(32) for _ in range(8)]
        await write_burst(dut, clk, addr, data)

        for i in range(8):
            test_data[addr+i*4] = data[i]


    # read data
    read_data = {}
    stop_event = Event()
    addr_queue = Queue()
    cocotb.start_soon(capture_reads(dut, clk, stop_event, read_data, addr_queue))

    for addr in range(0,96,32):
        dut.read.value = 1
        dut.addr.value = addr
        while not dut.cmd_ready.value:
            await ClockCycles(clk, 1)

        await addr_queue.put(addr)
        for i in range(1,8):
            await addr_queue.put(addr+i*4)
            await RisingEdge(clk)
    
    dut.read.value = 0

    await ClockCycles(clk, 50)
    stop_event.set()

    assert test_data == read_data, "Reads returned different data than what was written"
    print("test data")
    print([(a,hex(int(x))) for a,x in test_data.items()])
    print("read data")
    print([(a,hex(int(x))) for a,x in read_data.items()])




@cocotb.test()
async def row_crossing_test(dut):
    dut._log.setLevel("DEBUG")

    clk = dut.mem_clk
    reset = dut.reset

    # init system
    sdram = SDRAM(dut, clk)
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)

    test_data = {}
    for addr in [0, 1024, 0, 2**21]:
        data = [random.getrandbits(32) for _ in range(8)]
        await write_burst(dut, clk, addr, data)
        for i in range(8):
            test_data[addr+i*4] = data[i]


    # read data
    read_data = {}
    stop_event = Event()
    addr_queue = Queue()
    cocotb.start_soon(capture_reads(dut, clk, stop_event, read_data, addr_queue))

    for addr in [0, 2**21, 1024]:
        dut.read.value = 1
        dut.addr.value = addr
        while not dut.cmd_ready.value:
            await ClockCycles(clk, 1)

        await addr_queue.put(addr)
        for i in range(1,8):
            await addr_queue.put(addr+i*4)
            await RisingEdge(clk)
    
    dut.read.value = 0
    await ClockCycles(clk, 50)

    assert test_data == read_data, "Reads returned different data than what was written"
    print("test data")
    print([(a,hex(int(x))) for a,x in test_data.items()])
    print("read data")
    print([(a,hex(int(x))) for a,x in read_data.items()])




@cocotb.test()
async def read_to_write_test(dut):
    dut._log.setLevel("DEBUG")

    clk = dut.mem_clk
    reset = dut.reset

    # init system
    sdram = SDRAM(dut, clk)
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)

    dut.read.value = 1
    dut.addr.value = 0
    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)
    dut.read.value = 0
    
    await ClockCycles(clk, 3)

    data = [random.getrandbits(32) for _ in range(8)]
    await write_burst(dut, clk, 0, data)

    await ClockCycles(clk, 50)



@cocotb.test()
async def early_burst_stop_test(dut):
    dut._log.setLevel("DEBUG")

    clk = dut.mem_clk
    reset = dut.reset

    # init system
    sdram = SDRAM(dut, clk)
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)


    # read to write
    dut.read.value = 1
    dut.addr.value = 0
    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)
    dut.read.value = 0
    
    await ClockCycles(clk, 2)
    dut.stop.value = 1
    await ClockCycles(clk, 1)
    dut.stop.value = 0

    data = [random.getrandbits(32) for _ in range(8)]
    await write_burst(dut, clk, 0, data)

    await ClockCycles(clk, 50)

    # write to read
    data = [random.getrandbits(32) for _ in range(4)]
    await write_burst(dut, clk, 0, data)

    dut.read.value = 1
    dut.addr.value = 0
    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)
    dut.read.value = 0
    
    await ClockCycles(clk, 8)
    dut.stop.value = 0

    await ClockCycles(clk, 50)


@cocotb.test()
async def tRAS_test(dut):
    dut._log.setLevel("DEBUG")

    clk = dut.mem_clk
    reset = dut.reset

    # init system
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())
    await reset_dut(clk, reset)
    await ClockCycles(clk, 10)


    ## read to row 0
    dut.read.value = 1
    dut.stop.value = 1
    dut.addr.value = 0
    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)
    await ClockCycles(clk, 1)

    ## read to row 1
    dut.addr.value = 1024
    while not dut.cmd_ready.value:
        await ClockCycles(clk, 1)
    dut.read.value = 0
    dut.stop.value = 0


    await ClockCycles(clk, 50)



def test_runner():
    sim = get_runner("verilator")

    top_module = "sdram_controller"
    work_dir = Path(__file__).parent
    rtl_dir = work_dir.parent / "RTL/uncore/sdram"
    sources = list(rtl_dir.glob("*.sv"))

    sim.build(
        sources=sources,
        hdl_toplevel=top_module,
        always=False,
        waves=True,
        build_args=[
            "-Wno-SELRANGE",
            "-Wno-WIDTH",
            "--trace-fst",
            "--trace-structs",
        ],
        parameters = {
            "MEM_CLK_FREQ": 100_000_000
        }
    )

    sim.test(
        hdl_toplevel=top_module,
        test_module=Path(__file__).stem,
        waves=True,
        gui=True
    )

if __name__ == "__main__":
    test_runner()