
# ----------------------------------
# Memory-mapped host communication 
# ----------------------------------
    .section .tohost,"aw"
    .align 6
tohost:
    .dword 0

    .section .fromhost,"aw"
    .align 6
fromhost:
    .dword 0


.section .text.start
.global _start
.global _exit

_start:
    call main
    j _exit

_exit:
    la  t0, tohost      # address of tohost
    li  t1, 1           # convention: 1 = PASS
    sw  t1, 0(t0)       # write tohost -> Spike stops
1:  j 1b                # infinite loop

