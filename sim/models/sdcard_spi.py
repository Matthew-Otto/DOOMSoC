import cocotb
from cocotb.triggers import RisingEdge, FallingEdge

class SDCard:
    def __init__(self, dut, clk, cs, mosi, miso, mem={}):
        self.dut = dut
        self.clk = clk
        self.cs = cs
        self.mosi = mosi
        self.miso = miso
        self.memory = mem
        
        # Initialize MISO high
        self.miso.value = 1 
        
        # Start the background listener
        cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            # Wait for CS to be asserted (Active Low)
            if self.cs.value != 0:
                self.miso.value = 1
                await FallingEdge(self.cs)
                
            cmd = await self._receive_command()
            if cmd is None:
                continue # CS went high prematurely
                
            cmd_idx = cmd[0] & 0x3F # Mask out start bits
            addr = int.from_bytes(cmd[1:5], 'big')
            
            self._log(f"Received CMD{cmd_idx} with address 0x{addr:08X}")
            
            # Process Command
            if cmd_idx == 0:   # CMD0 - GO_IDLE_STATE
                await self._send_r1(0x01)
            elif cmd_idx == 8: # CMD8 - SEND_IF_COND
                # R7 Response: 1 byte R1 + 4 bytes echoed argument
                await self._send_r1(0x01) 
                # Echo back the exact 4 bytes of the argument the host sent
                await self._shift_byte(cmd[1]) # Usually 0x00
                await self._shift_byte(cmd[2]) # Usually 0x00
                await self._shift_byte(cmd[3]) # VHS (Usually 0x01)
                await self._shift_byte(cmd[4]) # Check Pattern (Usually 0xAA)
            elif cmd_idx == 17: # CMD17 - Read Block
                await self._send_r1(0x00)
                await self._wait_dummy_bytes(2)
                await self._send_data_block(addr)
            elif cmd_idx == 24: # CMD24 - Write Block
                await self._send_r1(0x00)
                await self._receive_data_block(addr)
            else:
                await self._send_r1(0x00)


    async def _shift_byte(self, tx_byte=0xFF):
        """Shifts out tx_byte on MISO, shifts in rx_byte from MOSI"""
        rx_byte = 0
        for i in range(8):
            # Drive MISO bit
            self.miso.value = (tx_byte >> (7 - i)) & 1

            # Sample MOSI bit
            await RisingEdge(self.clk)
            rx_byte = (rx_byte << 1) | int(self.mosi.value)

            if self.cs.value == 1:
                self.miso.value = 1
                return None # CS de-asserted, abort transfer
                    
        return rx_byte


    async def _receive_command(self):
        """Scans the bus for a valid 6-byte command packet"""
        rx = 0xFF
        # Wait for the start bits (0 followed by 1 -> 0x40 mask)
        while (rx & 0xC0) != 0x40:
            rx_opt = await self._shift_byte(0xFF)
            if rx_opt is None: return None
            rx = rx_opt
            
        cmd = bytearray([rx])
        # Read remaining 5 bytes (Arg + CRC)
        for _ in range(5):
            rx = await self._shift_byte(0xFF)
            if rx is None: return None
            cmd.append(rx)
            
        return cmd


    async def _send_r1(self, r1_val=0x00):
        """Sends the R1 response after a brief 1-byte NCR delay"""
        await self._shift_byte(0xFF) # NCR Delay
        await self._shift_byte(r1_val)


    async def _wait_dummy_bytes(self, count):
        for _ in range(count):
            if await self._shift_byte(0xFF) is None: return


    async def _send_data_block(self, addr):
        """Handles the transmission phase of CMD17"""
        await self._shift_byte(0xFE) # Data Start Token
        
        # Calculate memory offset (Assuming SDHC block addressing)
        offset = (addr * 512)
        
        # Send 512 bytes of payload
        for i in range(512):
            byte = self.memory.get(offset + i, 0)
            if await self._shift_byte(byte) is None: return
            
        # Send 2 bytes CRC
        await self._shift_byte(0xFF)
        await self._shift_byte(0xFF)


    async def _receive_data_block(self, addr):
        """Handles the reception and busy phase of CMD24"""
        # Wait for Data Token (0xFE)
        rx = 0xFF
        while rx != 0xFE:
            rx = await self._shift_byte(0xFF)
            if rx is None: return
            
        offset = (addr * 512)
        
        # Read 512 bytes of payload
        for i in range(512):
            rx = await self._shift_byte(0xFF)
            if rx is None: return
            self.memory[offset + i] = rx
            
        # Read 2 bytes CRC
        await self._shift_byte(0xFF)
        await self._shift_byte(0xFF)
        
        # Send Data Response Token (Data Accepted: 0x05)
        await self._shift_byte(0x05)
        
        # Busy State: Pull MISO low to indicate flashing to memory
        self._log(f"Writing block")
        for _ in range(16): # Simulate busy time (16 bytes)
            if await self._shift_byte(0x00) is None: return


    def _log(self, msg):
        self.dut._log.debug(f"[SDCard] {msg}")