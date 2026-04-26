import subprocess
import pty
import os
import re

# this is a dirty hack, but spike kinda sucks so it can't be avoided
class SpikeRunner:
    def __init__(self, elf_file):
        self.elf_file = elf_file
        self.first_run = True
        self.master_fd, slave_fd = pty.openpty()
        self.process = subprocess.Popen(
            ["spike", "-d", "--isa=RV32IM", elf_file],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            text=True
        )
        os.close(slave_fd)
        self.read_until(": ") # clear initial prompt

    def kill(self):
        self.process.kill()

    def read_until(self, delimiter):
        buf = ""
        while True:
            c = os.read(self.master_fd, 1).decode()  # read one byte at a time
            if not c:
                break  # EOF
            buf += c
            if delimiter in buf:
                break
        return buf[:-2].strip()

    def exec_cmd(self, cmd):
        os.write(self.master_fd, (cmd + '\n').encode())
        self.read_until(cmd) # clear cmd from output
        output = self.read_until("\n: ")
        return output
    
    def dump_regfile(self):
        reg_dump = self.exec_cmd("reg 0")
        self.regfile = [int(v,16) for v in reg_dump.split() if ":" not in v]

    def step(self): # returns (pc, instr)
        # crazy recursion is totally fine
        if self.first_run:
            self.first_run = 0
            return self.run_until(0x80000000)
        
        else:
            output = self.exec_cmd("r 1")
            self.dump_regfile()
            data = [int(v, 16) for v in tuple(re.findall(r"0x[0-9a-fA-F]+", output))]
            return data[0], data[1]
    
    def run_until(self, untilpc):
        while True:
            pc, instr = self.step()
            if untilpc == pc:
                return pc, instr

    def regs(self):
        return self.regfile
