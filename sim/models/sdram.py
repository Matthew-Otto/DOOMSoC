import random
import cocotb
from cocotb.triggers import RisingEdge
from cocotb.types import LogicArray

class SDRAM:
    def __init__(self, dut, clock_signal, cas_latency=3, burst_length=8):
        self.dut = dut
        self.clock = clock_signal
        self.cas_latency = cas_latency
        self.burst_length = burst_length
        
        self.memory = {}
        self.active_rows = [None]*4
        self.read_pipeline = [None]*(cas_latency-1)
        
        # Track ongoing bursts
        self.burst_read = None  # Expected format: {'b': bank, 'r': row, 'c': col, 'rem': count}
        self.burst_write = None

        self.bus_read_data = dut.mem_controller_i.bus_read_data
        
        cocotb.start_soon(self._run())


    def _execute_write(self, bank, row, col):
        # extract write data
        dq_val = self.dut.IO_sdram_dq.value
        write_data = int(dq_val)
            
        dqm = int(self.dut.O_sdram_dqm.value)
        
        # Apply DQM (Data Masking). Active High ignores the byte.
        current_data = self.memory.get((bank, row, col), 0x00000000)
        write_mask = 0x00000000
        
        if not (dqm & 0b0001): write_mask |= 0x000000FF # Keep Byte 0
        if not (dqm & 0b0010): write_mask |= 0x0000FF00 # Keep Byte 1
        if not (dqm & 0b0100): write_mask |= 0x00FF0000 # Keep Byte 2
        if not (dqm & 0b1000): write_mask |= 0xFF000000 # Keep Byte 3
        
        # Splice the new bytes into the existing word
        new_data = (current_data & ~write_mask) | (write_data & write_mask)
        self.memory[(bank, row, col)] = new_data
        
        self.dut._log.debug(f"SDRAM [WRITE]: Bank {bank}, Row {row}, Col {col} <- 0x{new_data:08x}")


    async def _run(self):
        while True:
            await RisingEdge(self.clock)
            
            # Read Pipeline
            read_data = self.read_pipeline.pop(0)
            if read_data is not None:
                self.bus_read_data.value = read_data
            else:
                self.bus_read_data.value = LogicArray("z" * 32)
                
            self.read_pipeline.append(None)

            # Read CMD
            ras_n = int(self.dut.O_sdram_ras_n.value)
            cas_n = int(self.dut.O_sdram_cas_n.value)
            wen_n = int(self.dut.O_sdram_wen_n.value)
            cmd = (ras_n, cas_n, wen_n)
            
            bank = int(self.dut.O_sdram_ba.value)
            addr = int(self.dut.O_sdram_addr.value)
            
            # Burst interruption
            # Any valid command other than NOP automatically interrupts an active burst
            if cmd != (1, 1, 1):
                self.burst_read = None
                self.burst_write = None

            match cmd:
                case (1, 1, 1): # NOP
                    # Continue ongoing read burst
                    if self.burst_read:
                        b, r, c, rem = self.burst_read['b'], self.burst_read['r'], self.burst_read['c'], self.burst_read['rem']
                        
                        data = self.memory.get((b, r, c), random.getrandbits(32))
                        self.read_pipeline[-1] = data 
                        self.dut._log.debug(f"SDRAM [READ]: Bank {b}, Row {r}, Col {c} -> 0x{data:08x}")
                        
                        if rem > 1:
                            self.burst_read = {'b': b, 'r': r, 'c': c + 1, 'rem': rem - 1}
                        else:
                            self.burst_read = None
                            
                    # Continue ongoing write burst
                    elif self.burst_write:
                        b, r, c, rem = self.burst_write['b'], self.burst_write['r'], self.burst_write['c'], self.burst_write['rem']
                        
                        self._execute_write(b, r, c)
                        
                        if rem > 1:
                            self.burst_write = {'b': b, 'r': r, 'c': c + 1, 'rem': rem - 1}
                        else:
                            self.burst_write = None
                            
                # BST (Burst Terminate)
                case (1, 1, 0):
                    # Active bursts were already cleared by the interruption logic above. 
                    self.dut._log.info("SDRAM [BST]: Burst Terminated Early")
            
                # ACT (Active) - Open a row in a specific bank
                case (0, 1, 1):
                    self.active_rows[bank] = addr
                    self.dut._log.info(f"SDRAM [ACT]: Bank {bank}, Row {addr}")
                
                # PRE (Precharge) - Close a row
                case (0, 1, 0):
                    if (addr >> 10) & 1:
                        for b in range(4): self.active_rows[b] = None
                        self.dut._log.info("SDRAM [PRE]: All Banks")
                    else:
                        self.active_rows[bank] = None
                        self.dut._log.info(f"SDRAM [PRE]: Bank {bank}")
                
                # RD (Read)
                case (1, 0, 1):
                    col = addr & 0xFF
                    row = self.active_rows[bank]
                    if row is None:
                        raise Exception(f"SDRAM [READ ERROR]: Bank {bank} has no active row!")
                    else:
                        data = self.memory.get((bank, row, col), random.getrandbits(32))
                        self.read_pipeline[-1] = data 
                        self.dut._log.debug(f"SDRAM [READ]: Bank {bank}, Row {row}, Col {col} -> 0x{data:08x}")
                        
                        # Initialize Read Burst tracking for future NOP cycles
                        if self.burst_length > 1:
                            self.burst_read = {'b': bank, 'r': row, 'c': (col+1) % 256, 'rem': self.burst_length - 1}
                    
                # WR (Write)
                case (1, 0, 0):
                    col = addr & 0xFF
                    row = self.active_rows[bank]
                    if row is None:
                        raise Exception(f"SDRAM [WRITE ERROR]: Bank {bank} has no active row!")
                    else:
                        self._execute_write(bank, row, col)
                        
                        # Initialize Write Burst tracking for future NOP cycles
                        if self.burst_length > 1:
                            self.burst_write = {'b': bank, 'r': row, 'c': (col+1) % 256, 'rem': self.burst_length - 1}
                    
                # LMR (Load Mode Register)
                case (0, 0, 0):
                    self.dut._log.info("SDRAM [LMR]: Load Mode Register")
                    
                # REF (Auto Refresh)
                case (0, 0, 1):
                    self.dut._log.info("SDRAM [REF]: Auto Refresh")

    def dump(self, start_addr, end_addr):
        for addr in range(start_addr, end_addr):
            bank = (addr >> 19) & 0x3
            row = (addr >> 8) & 0x7FF
            col = addr & 0xFF
            data = self.memory.get((bank, row, col), 0xdeadbeef)
            self.dut._log.debug(f"{addr:x} | 0x{data:x}")
