import os
import pexpect
import re
import sys

# this is a dirty hack, but spike kinda sucks so it can't be avoided
class SpikeRunner:
    def __init__(self, elf_file):
        self.elf_file = elf_file
        self.first_run = True

        self.entry_pc = "0x20000000"

        cmd = [
            "spike",
            "-d",
            "--isa=RV32IM",
            "-m0x20000000:0x2000,0x30000000:0x10000,0x80000000:0x800000",
            f"--pc={self.entry_pc}",
            elf_file
        ]

        print(f"Launching Spike simulator with {elf_file} | {" ".join(cmd)}")
        env = os.environ.copy()
        env['TERM'] = 'dumb' # strips out terminal characters

        self.process = pexpect.spawn(cmd[0], cmd[1:], env=env, encoding="utf-8")
            
        match_index = self.process.expect([
            r": ",
            r"terminate called",
        ])
        
        # If matched on anything except index 0 (the prompt), it's probably a crash
        if match_index != 0:
            print("\nERROR:")
            # Grab the matched text, what came before it, and anything left in the buffer
            matched_text = str(self.process.after) if self.process.after else ""
            before_text = str(self.process.before) if self.process.before else ""
            remaining_text = self.process.read() if not self.process.closed else ""
            
            print((before_text + matched_text + remaining_text).strip())
            sys.exit(1)
        self.process.setecho(False)


    def exec_cmd(self, cmd):
        #print(f"Executing: '{cmd}'")
        self.process.sendline(cmd)
        self.process.expect(r"\n: ")
        output = self.process.before
        return output
    
    def dump_regfile(self):
        reg_dump = self.exec_cmd("reg 0")
        self.regfile = [int(v,16) for v in reg_dump.split() if ":" not in v]

    def run_until(self, untilpc):
        self.exec_cmd(f"until pc 0 {untilpc}")

    def step(self): # returns (pc, instr)
        if self.first_run:
            self.first_run = 0
            self.run_until(self.entry_pc)
        
        output = self.exec_cmd("r 1")
        print(output)
        self.dump_regfile()
        data = [int(v, 16) for v in tuple(re.findall(r"0x[0-9a-fA-F]+", output))]
        return data[0], data[1]


    def regs(self):
        return self.regfile
