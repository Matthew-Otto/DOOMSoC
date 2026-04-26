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
    # drive memory
    rd_addr = 0
    while True:
        await RisingEdge(clk)
        
        # write
        wr_addr = int(dut.d_addr.value)
        data = 0
        width = 0
        if dut.d_we.value[0]:
            memory[wr_addr] = int(dut.d_wr_data.value[7:0])
            data |= int(dut.d_wr_data.value[7:0])
            width = 8
        if dut.d_we.value[1]:
            memory[wr_addr+1] = int(dut.d_wr_data.value[15:8])
            data |= int(dut.d_wr_data.value[15:8]) << 8
            width = 16
        if dut.d_we.value[2]:
            memory[wr_addr+2] = int(dut.d_wr_data.value[23:16])
            data |= int(dut.d_wr_data.value[23:16]) << 16
            width = 24
        if dut.d_we.value[3]:
            memory[wr_addr+3] = int(dut.d_wr_data.value[31:24])
            data |= int(dut.d_wr_data.value[31:24]) << 24
            width = 32
        if dut.d_we.value:
            dut._log.debug(f"WRITE mem: {width} bits: addr=0x{wr_addr:08X} data=0x{data:08X}")
        
        # read
        if dut.cpu.LSU_i.is_load_op.value:
            rd_addr = int(dut.d_addr.value)
            data = read_word(memory, rd_addr)
            dut.d_rd_data.value = data
            dut._log.debug(f"READ mem: addr=0x{rd_addr:08X} data=0x{data:08X}")
        
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