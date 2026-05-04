import random
import logging
import cocotb
from cocotb.triggers import RisingEdge
from cocotb.types import LogicArray

class SDRAM:
    def __init__(self, dut, clock_signal, mem={}, cas_latency=3, burst_length=8):
        self.dut = dut
        self.clock = clock_signal
        self.cas_latency = cas_latency
        self.burst_length = burst_length
        
        # Flattened memory: Key is a single integer address instead of a tuple
        self.memory = mem
        self.active_rows = [None] * 4
        self.read_pipeline = [None] * (cas_latency - 1)
        
        self.burst_read = None
        self.burst_write = None

        # --- OPTIMIZATION: Pre-allocate static objects ---
        self.HIGH_Z = LogicArray("z" * 32)
        
        # --- OPTIMIZATION: Cache logger check ---
        self._is_debug = dut._log.isEnabledFor(logging.DEBUG)
        self._is_info = dut._log.isEnabledFor(logging.INFO)
        
        # --- OPTIMIZATION: Cache signal handles ---
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
        """Helper to flatten bank, row, and col into a single integer key."""
        return (bank << 19) | (row << 8) | col

    def _execute_write(self, bank, row, col):
        try:
            write_data = int(self._dq.value)
            dqm = int(self._dqm.value)
        except ValueError:
            # Handle floating/unknown states gracefully during write
            write_data = 0
            dqm = 0b1111 # Mask out everything if invalid

        addr = self._get_addr(bank, row, col)
        current_data = self.memory.get(addr, 0x00000000)
        write_mask = 0x00000000
        
        if not (dqm & 0b0001): write_mask |= 0x000000FF
        if not (dqm & 0b0010): write_mask |= 0x0000FF00
        if not (dqm & 0b0100): write_mask |= 0x00FF0000
        if not (dqm & 0b1000): write_mask |= 0xFF000000
        
        new_data = (current_data & ~write_mask) | (write_data & write_mask)
        self.memory[addr] = new_data
        
        # Lazy logging: String is only evaluated if DEBUG is actually on
        if self._is_debug:
            self.dut._log.debug("SDRAM [WRITE]: Bank %d, Row %d, Col %d <- 0x%08x", bank, row, col, new_data)

    async def _run(self):
        while True:
            await RisingEdge(self.clock)
            
            # Read Pipeline Execution
            read_data = self.read_pipeline.pop(0)
            if read_data is not None:
                self.bus_read_data.value = read_data
            else:
                self.bus_read_data.value = self.HIGH_Z
                
            self.read_pipeline.append(None)

            # Fast command parsing
            try:
                cmd = (int(self._ras_n.value), int(self._cas_n.value), int(self._wen_n.value))
            except ValueError:
                # If command lines are 'x' or 'z', ignore the cycle
                continue
            
            # Any valid command other than NOP automatically interrupts an active burst
            if cmd != (1, 1, 1):
                self.burst_read = None
                self.burst_write = None

            match cmd:
                case (1, 1, 1): # NOP
                    if self.burst_read:
                        b, r, c, rem = self.burst_read['b'], self.burst_read['r'], self.burst_read['c'], self.burst_read['rem']
                        
                        addr = self._get_addr(b, r, c)
                        data = self.memory.get(addr, random.getrandbits(32))
                        self.read_pipeline[-1] = data 
                        
                        if self._is_debug:
                            self.dut._log.debug("SDRAM [READ]: Bank %d, Row %d, Col %d -> 0x%08x", b, r, c, data)
                        
                        if rem > 1:
                            self.burst_read = {'b': b, 'r': r, 'c': (c + 1) % 256, 'rem': rem - 1}
                        else:
                            self.burst_read = None
                            
                    elif self.burst_write:
                        b, r, c, rem = self.burst_write['b'], self.burst_write['r'], self.burst_write['c'], self.burst_write['rem']
                        self._execute_write(b, r, c)
                        
                        if rem > 1:
                            self.burst_write = {'b': b, 'r': r, 'c': (c + 1) % 256, 'rem': rem - 1}
                        else:
                            self.burst_write = None
                            
                case (1, 1, 0): # BST
                    if self._is_info: self.dut._log.info("SDRAM [BST]: Burst Terminated Early")
            
                case (0, 1, 1): # ACT
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    self.active_rows[bank] = addr
                    if self._is_info: self.dut._log.info("SDRAM [ACT]: Bank %d, Row %d", bank, addr)
                
                case (0, 1, 0): # PRE
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    if (addr >> 10) & 1:
                        for b in range(4): self.active_rows[b] = None
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
                    else:
                        mem_addr = self._get_addr(bank, row, col)
                        data = self.memory.get(mem_addr, random.getrandbits(32))
                        self.read_pipeline[-1] = data 
                        
                        if self._is_debug:
                            self.dut._log.debug("SDRAM [READ]: Bank %d, Row %d, Col %d -> 0x%08x", bank, row, col, data)
                        
                        if self.burst_length > 1:
                            self.burst_read = {'b': bank, 'r': row, 'c': (col + 1) % 256, 'rem': self.burst_length - 1}
                    
                case (1, 0, 0): # WR
                    bank, addr = int(self._ba.value), int(self._addr.value)
                    col = addr & 0xFF
                    row = self.active_rows[bank]
                    if row is None:
                        raise Exception(f"SDRAM [WRITE ERROR]: Bank {bank} has no active row!")
                    else:
                        self._execute_write(bank, row, col)
                        
                        if self.burst_length > 1:
                            self.burst_write = {'b': bank, 'r': row, 'c': (col + 1) % 256, 'rem': self.burst_length - 1}
                    
                case (0, 0, 0): # LMR
                    if self._is_info: self.dut._log.info("SDRAM [LMR]: Load Mode Register")
                    
                case (0, 0, 1): # REF
                    if self._is_info: self.dut._log.info("SDRAM [REF]: Auto Refresh")

    def dump(self, start_addr, end_addr):
        """Optimized dump utilizing the flattened integer addresses."""
        for addr in range(start_addr, end_addr):
            data = self.memory.get(addr, 0xdeadbeef)
            if self._is_debug:
                self.dut._log.debug("%x | 0x%x", addr, data)