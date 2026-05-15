// Load DOOM from SD Card and jump to engine execution

#include <stdint.h>

// Address Map
#define SDCARD_BASE 0x20000000
#define SDRAM_BASE  0x80000000

#define APP_SIZE    0x00010000
#define PROG_ENTRY  0x80000000

void bootloader(void);

void __attribute__((naked, section(".boot"))) _start(void) {
    __asm__ volatile (
        // Initialize stack pointer
        "la sp, __stack_top \n"
        
        // Jump to C function
        "j bootloader \n"
    );
}

void __attribute__((noreturn)) bootloader(void) {
    // Copy the program from SD Card to SDRAM
    volatile uint32_t *src = (volatile uint32_t *)SDCARD_BASE;
    volatile uint32_t *dst = (volatile uint32_t *)SDRAM_BASE;
    uint32_t words_to_copy = APP_SIZE / 4;
    
    for (uint32_t i = 0; i < words_to_copy; i++) {
        dst[i] = src[i];
    }

    // Jump to program entry
    ((void (*)(void))PROG_ENTRY)();

    while (1) {}
}