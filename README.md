# DOOMSoC

DOOMSoC is a custom RISC-V CPU designed to run DOOM at full speed and resolution on a Gowin Tang nano 20K.

A complete writeup can be found at https://matthew-otto.github.io/projects/doomsoc.

The AXI crossbar used in this design comes from the pulp-platform: https://github.com/pulp-platform/axi

This repo contains a copy of the modified DOOM source code along with the original shareware WAD.

The original DOOM sourcecode can be found at https://github.com/id-Software/DOOM


#### Deps:

[oss-cad-suite-build-bin](https://github.com/YosysHQ/oss-cad-suite-build)

[riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain) (`risc-v` package group on arch)
