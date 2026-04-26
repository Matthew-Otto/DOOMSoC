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



# measure sim speed
import time
from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time

async def log_sim_speed(dut, clk, sample_period=10000):
    """
    Call this at the start of the test:
    cocotb.start_soon(log_sim_speed(dut, clk))
    """
    # measure clock period
    start_time = time.perf_counter()
    await ClockCycles(clk, 2)
    cycle_period_fs = get_sim_time("fs")
    
    try:
        period_start = start_time
        while True:
            await ClockCycles(clk, sample_period)
            cycles = sample_period
            
            elapsed_real_time = time.perf_counter() - period_start
            period_start = time.perf_counter()

            speed = cycles / elapsed_real_time
                
            dut._log.info(f"Sim Speed: {speed:,.0f} cycles / second")
    finally:
        test_duration = time.perf_counter() - start_time
        cycle_count = get_sim_time("fs") / cycle_period_fs
        cycles_per_second = cycle_count / test_duration
        dut._log.info(f"Total Average Sim Speed: {cycles_per_second:,.0f} cycles / second")


            

### core bringup ########################

def read_word(memory, addr):
    data  = memory.get(addr, 0)
    data |= memory.get(addr+1, 0) << 8
    data |= memory.get(addr+2, 0) << 16
    data |= memory.get(addr+3, 0) << 24
    return data

async def sim_instr_mem(dut, clk ,memory):
    # drive i_mem
    while True:
        await RisingEdge(clk)
        addr = int(dut.i_addr.value)
        #dut._log.debug(f"Fetching instruction @ address {addr}")
        data = read_word(memory,addr)
        dut.i_rd_data.value = data
        if not dut.cpu.fetch_stall.value:
            dut._log.debug(f"Fetched 0x{data:08X} from address 0x{addr:08X}")



async def sim_data_mem(dut, clk, memory):
    d_addr        = dut.d_addr
    d_we          = dut.d_we
    d_wr_data_hdl = dut.d_wr_data
    d_rd_data_hdl = dut.d_rd_data
    is_load_hdl   = dut.cpu.loadstore_unit.is_load_op
    
    while True:
        await RisingEdge(clk)
        we = int(d_we.value)
        if we:
            wr_addr = int(d_addr.value)
            wr_data = int(d_wr_data_hdl.value)
            
            if we & 0b0001: memory[wr_addr]     = wr_data & 0xFF
            if we & 0b0010: memory[wr_addr + 1] = (wr_data >> 8) & 0xFF
            if we & 0b0100: memory[wr_addr + 2] = (wr_data >> 16) & 0xFF
            if we & 0b1000: memory[wr_addr + 3] = (wr_data >> 24) & 0xFF
                
            dut._log.debug("WRITE mem: addr=0x%08X data=0x%08X (we=0x%X)", wr_addr, wr_data, we)

        # Read logic
        if is_load_hdl.value == 1:
            rd_addr = int(d_addr.value)
            data = read_word(memory, rd_addr)
            d_rd_data_hdl.value = data
            
            dut._log.debug("READ mem: addr=0x%08X data=0x%08X", rd_addr, data)


        
def parse_verilog_hex(filename):
    memory = {}
    address = 0

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            if line.startswith('@'):
                address = int(line[1:], 16)
            else:
                line_bytes = bytes.fromhex(line)
                for byte in line_bytes:
                    memory[address] = int(byte)
                    address += 1

    return memory



# this a dirty (and probably very fragile) hack
# the next cocotb update will likely break the Bus class anyway so this is tomorrow's problem
from cocotbext.axi import AxiBus
def bind_pulp_axi(pulp_intf):
    """
    Wraps a PULP AXI interface and returns a cocotbext-axi AxiBus.
    """
    class AxiDummy:
        pass
        
    dummy = AxiDummy()

    # -------------------------------------------------------------------
    # THE FIX: Copy simulator metadata so cocotb can print debug logs
    # -------------------------------------------------------------------
    dummy._log = pulp_intf._log
    dummy._name = pulp_intf._name
    # Safely grab _path if the simulator provides it
    dummy._path = getattr(pulp_intf, '_path', pulp_intf._name)

    # -------------------------------------------------------------------
    # SIGNAL MAPPING
    # -------------------------------------------------------------------
    mapping = {
        'awid': 'aw_id', 'awaddr': 'aw_addr', 'awlen': 'aw_len', 'awsize': 'aw_size', 
        'awburst': 'aw_burst', 'awvalid': 'aw_valid', 'awready': 'aw_ready', 
        'awlock': 'aw_lock', 'awcache': 'aw_cache', 'awprot': 'aw_prot', 
        'awqos': 'aw_qos', 'awregion': 'aw_region', 'awuser': 'aw_user',
        
        'wdata': 'w_data', 'wstrb': 'w_strb', 'wlast': 'w_last', 
        'wvalid': 'w_valid', 'wready': 'w_ready', 'wuser': 'w_user',
        
        'bid': 'b_id', 'bresp': 'b_resp', 'bvalid': 'b_valid', 
        'bready': 'b_ready', 'buser': 'b_user',
        
        'arid': 'ar_id', 'araddr': 'ar_addr', 'arlen': 'ar_len', 'arsize': 'ar_size', 
        'arburst': 'ar_burst', 'arvalid': 'ar_valid', 'arready': 'ar_ready', 
        'arlock': 'ar_lock', 'arcache': 'ar_cache', 'arprot': 'ar_prot', 
        'arqos': 'ar_qos', 'arregion': 'ar_region', 'aruser': 'ar_user',
        
        'rid': 'r_id', 'rdata': 'r_data', 'rresp': 'r_resp', 
        'rlast': 'r_last', 'rvalid': 'r_valid', 'rready': 'r_ready', 'ruser': 'r_user'
    }

    # Attach the handles
    for std_name, pulp_name in mapping.items():
        if hasattr(pulp_intf, pulp_name):
            setattr(dummy, std_name, getattr(pulp_intf, pulp_name))

    return AxiBus.from_prefix(dummy, "")