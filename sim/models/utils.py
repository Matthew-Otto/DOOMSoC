# configure logging to file
import logging

def setup_file_logger(logger, level=logging.DEBUG, file="sim.log"):
    path = "../" + file
    logger.setLevel(level)
    fh = logging.FileHandler(path, mode="w")
    fh.setLevel(level)
    logger.addHandler(fh)



# reset design
from cocotb.triggers import ClockCycles, RisingEdge

async def reset_dut(clk, rst, active_low=False):
    await RisingEdge(clk)
    rst.value = not active_low
    await ClockCycles(clk, 5)
    rst.value = active_low
    await ClockCycles(clk, 5)
    print("DUT reset")