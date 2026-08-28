import os
import pexpect
import re
import sys

# this is a dirty hack, but spike kinda sucks so it can't be avoided
class SpikeRunner:
    def __init__(self, elf_file):
        self.elf_file = elf_file
        self.entry_pc = "0x20000000"

        self.cmd = [
            "spike",
            "-d",
            "--isa=RV32IM",
            "-m0x20000000:0x400,0x30000000:0x10000,0x40000000:0x10000,0x80000000:0x800000",
            f"--pc={self.entry_pc}",
            elf_file
        ]

        self.instr_pattern = re.compile(r"(0x[0-9a-fA-F]+)\s+\((0x[0-9a-fA-F]+)\)\s+(.*)")
        self.prompt_regex = r"(?:\r?\n|^): "

        self.reset()


    def reset(self):
        if hasattr(self, "process"):
            self.process.terminate(force=True)

        print(f"Launching Spike simulator with {self.elf_file} | {' '.join(self.cmd)}")
        env = os.environ.copy()
        env['TERM'] = 'dumb' # strips out terminal characters

        self.process = pexpect.spawn(self.cmd[0], self.cmd[1:], env=env, encoding="utf-8")
        self.process.setecho(False)
            
        match_index = self.process.expect([
            self.prompt_regex,
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

        self.regfile = []
        self.run_until(self.entry_pc)

        

    def exec_cmd(self, cmd):
        print(f"Executing: '{cmd}'")
        self.process.sendline(cmd)
        self.process.expect(self.prompt_regex)
        output = self.process.before
        if output.startswith(cmd):
            output = output[len(cmd):]
        return output.strip()
    
    def parse_instruction(self, line): # returns (pc, encoded instr, asm instr)
        pattern = r"(0x[0-9a-fA-F]+)\s+\((0x[0-9a-fA-F]+)\)\s+(.*)"
        match = self.instr_pattern.search(line)
        if match:
            return match.group(1), match.group(2), match.group(3).strip()
        return None


    def run_until(self, untilpc):
        self.exec_cmd(f"until pc 0 {untilpc}")

    def step(self):    
        output = self.exec_cmd("r 1")
        print(output)
        self.dump_regfile()
        return self.parse_instruction(output)
    
    def stepn(self, n=1):
        output = self.exec_cmd(f"r {n}")
        lines = output.splitlines()
        parsed_instructions = []
        for line in lines:
            if instr:= self.parse_instruction(line):
                parsed_instructions.append(instr)
                
        return parsed_instructions


    def dump_regfile(self):
        reg_dump = self.exec_cmd("reg 0")
        self.regfile = [int(v,16) for v in reg_dump.split() if ":" not in v]

    def format_regs(self, regs):
        reg_string = ""
        abi_names = [
            "00", "ra",  "sp",  "gp",  "tp", "t0", "t1", "t2",
            "s0", "s1",  "a0",  "a1",  "a2", "a3", "a4", "a5",
            "a6", "a7",  "s2",  "s3",  "s4", "s5", "s6", "s7",
            "s8", "s9",  "s10", "s11", "t3", "t4", "t5", "t6"
        ]

        num_rows = 8
        num_cols = 4

        for row in range(num_rows):
            row_entries = []
            for col in range(num_cols):
                # Calculate index for column-major order
                reg_num = row + (col * num_rows)
                alias = abi_names[reg_num]
                val = regs[reg_num]
                val_str = f"0x{val & 0xFFFFFFFF:08x}" 
                entry = f"x{reg_num:<2} ({alias+')':<4}: {val_str}"
                row_entries.append(entry)
                
            reg_string += "    ".join(row_entries)
            reg_string += "\n"
        return reg_string


    
    def get_state_at(self, cycle_cnt):
        """runs the simulator for <cycle_cnt> cycles and then returns the system state"""
        self.reset()
        self.stepn(cycle_cnt-1)
        instr = self.step()
        regs = self.format_regs(self.regfile)
        return instr, regs

