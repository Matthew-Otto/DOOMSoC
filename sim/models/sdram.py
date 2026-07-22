import random
import logging
import cocotb
from cocotb.triggers import RisingEdge
from cocotb.types import LogicArray

class SDRAM:
    def __init__(self, dut, clock, mem=None, cas_latency=3, burst_length=8):
        self.dut = dut
        self.clock = clock
        self.cas_latency = cas_latency
        self.burst_length = burst_length
        
        self.memory = mem if mem is not None else {}
        self.active_rows = [None] * 4
        
        self.pipe_len = cas_latency - 1
        self.read_pipeline = [None] * self.pipe_len
        self.pipe_idx = 0
        
        self.burst_type = 0 # 0=None, 1=Read, 2=Write
        self.burst_b = 0
        self.burst_r = 0
        self.burst_c = 0
        self.burst_rem = 0

        self.HIGH_Z = LogicArray("z" * 32)
        self._last_driven = None
        
        self._dqm_mask_lut = tuple(
            ((~d & 1) * 0xFF) | (((~d >> 1) & 1) * 0xFF00) | 
            (((~d >> 2) & 1) * 0xFF0000) | (((~d >> 3) & 1) * 0xFF000000)
            for d in range(16)
        )
        
        self._is_debug = dut._log.isEnabledFor(logging.DEBUG)
        self._is_info = dut._log.isEnabledFor(logging.INFO)
        
        self._ras_n = dut.O_sdram_ras_n
        self._cas_n = dut.O_sdram_cas_n
        self._wen_n = dut.O_sdram_wen_n
        self._ba = dut.O_sdram_ba
        self._addr = dut.O_sdram_addr
        self._dq = dut.IO_sdram_dq
        self._dqm = dut.O_sdram_dqm
        self.bus_read_data = dut.bus_read_data
        
        cocotb.start_soon(self._run())

    def _get_addr(self, bank, row, col):
        return (bank << 19) | (row << 8) | col

    def _execute_write(self, bank, row, col):
        try:
            write_data = int(self._dq.value)
            dqm = int(self._dqm.value)
        except ValueError:
            write_data = 0
            dqm = 0b1111 # Mask out everything if invalid

        addr = self._get_addr(bank, row, col)
        current_data = self.memory.get(addr, 0x00000000)
        
        write_mask = self._dqm_mask_lut[dqm & 0xF]
        
        new_data = (current_data & ~write_mask) | (write_data & write_mask)
        self.memory[addr] = new_data
        
        if self._is_debug:
            self.dut._log.debug("SDRAM [WRITE]: Bank %d, Row %d, Col %d <- 0x%08x", bank, row, col, new_data)

    async def _run(self):
        while True:
            await RisingEdge(self.clock)
            
            read_data = self.read_pipeline[self.pipe_idx]
            self.read_pipeline[self.pipe_idx] = None # Clear slot for reuse
            
            # --- VPI Call Optimization ---
            if read_data is not None:
                self.bus_read_data.value = read_data
                self._last_driven = read_data
            elif self._last_driven is not None:
                # Only write HIGH_Z if we aren't already driving HIGH_Z
                self.bus_read_data.value = self.HIGH_Z
                self._last_driven = None
                
            pipe_target = (self.pipe_idx - 1) % self.pipe_len
            self.pipe_idx = (self.pipe_idx + 1) % self.pipe_len

            try:
                cmd = (int(self._ras_n.value), int(self._cas_n.value), int(self._wen_n.value))
            except ValueError:
                continue
            
            if cmd != (1, 1, 1):
                self.burst_type = 0 # Cancel burst on new valid command

            match cmd:
                case (1, 1, 1): # NOP
                    if self.burst_type == 1: # Read
                        addr = (self.burst_b << 19) | (self.burst_r << 8) | self.burst_c
                        data = self.memory.get(addr, 0xdeadbeef)
                        self.read_pipeline[pipe_target] = data 
                        
                        if self._is_debug:
                            self.dut._log.debug("SDRAM [READ]: Bank %d, Row %d, Col %d -> 0x%08x", self.burst_b, self.burst_r, self.burst_c, data)
                        
                        if self.burst_rem > 1:
                            self.burst_c = (self.burst_c + 1) % 256
                            self.burst_rem -= 1
                        else:
                            self.burst_type = 0
                            
                    elif self.burst_type == 2: # Write
                        self._execute_write(self.burst_b, self.burst_r, self.burst_c)
                        
                        if self.burst_rem > 1:
                            self.burst_c = (self.burst_c + 1) % 256
                            self.burst_rem -= 1
                        else:
                            self.burst_type = 0
                            
                case (1, 1, 0): # BST
                    if self._is_info: self.dut._log.info("SDRAM [BST]: Burst Terminated Early")
            
                case (0, 1, 1): # ACT
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    self.active_rows[bank] = addr
                    if self._is_info: self.dut._log.info("SDRAM [ACT]: Bank %d, Row %d", bank, addr)
                
                case (0, 1, 0): # PRE
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    if (addr >> 10) & 1:
                        self.active_rows = [None] * 4
                        if self._is_info: self.dut._log.info("SDRAM [PRE]: All Banks")
                    else:
                        self.active_rows[bank] = None
                        if self._is_info: self.dut._log.info("SDRAM [PRE]: Bank %d", bank)
                
                case (1, 0, 1): # RD
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    col = addr & 0xFF
                    row = self.active_rows[bank]
                    if row is None:
                        raise Exception(f"SDRAM [READ ERROR]: Bank {bank} has no active row!")
                    
                    mem_addr = self._get_addr(bank, row, col)
                    data = self.memory.get(mem_addr, 0xdeadbeef)
                    self.read_pipeline[pipe_target] = data 
                    
                    if self._is_debug:
                        self.dut._log.debug("SDRAM [READ]: Bank %d, Row %d, Col %d -> 0x%08x", bank, row, col, data)
                    
                    if self.burst_length > 1:
                        self.burst_type = 1
                        self.burst_b, self.burst_r, self.burst_c = bank, row, (col + 1) % 256
                        self.burst_rem = self.burst_length - 1
                    
                case (1, 0, 0): # WR
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    col = addr & 0xFF
                    row = self.active_rows[bank]
                    if row is None:
                        raise Exception(f"SDRAM [WRITE ERROR]: Bank {bank} has no active row!")
                    
                    self._execute_write(bank, row, col)
                    
                    if self.burst_length > 1:
                        self.burst_type = 2
                        self.burst_b, self.burst_r, self.burst_c = bank, row, (col + 1) % 256
                        self.burst_rem = self.burst_length - 1
                    
                case (0, 0, 0): # LMR
                    if self._is_info: self.dut._log.info("SDRAM [LMR]: Load Mode Register")
                    
                case (0, 0, 1): # REF
                    if self._is_info: self.dut._log.info("SDRAM [REF]: Auto Refresh")

    def dump(self, start_addr, end_addr):
        for addr in range(start_addr, end_addr):
            data = self.memory.get(addr, 0xdeadbeef)
            if self._is_debug:
                self.dut._log.debug("%x | 0x%x", addr, data)
