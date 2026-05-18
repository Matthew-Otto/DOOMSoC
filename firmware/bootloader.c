// Load DOOM from SD Card and jump to engine execution

#include <stdint.h>

// Address Map
#define SDCARD_BASE 0x40000000
#define SDRAM_BASE  0x80000000

#define APP_SIZE    0x00010000
#define PROG_ENTRY  0x80000000

// Linker aliases
extern uint8_t _sidata[];
extern uint8_t _sdata[];
extern uint8_t _edata[];
extern uint8_t _sbss[];
extern uint8_t _ebss[];


void bootloader(void);

void __attribute__((naked, section(".boot"))) _start(void) {
    // Initialize stack pointer
    __asm("la sp, __stack_top");
    // Jump to C function
    __asm("j bootloader");
}

void __attribute__((noreturn)) bootloader(void) {
    // copy .data section from ROM to RAM
    uint8_t* src = _sidata;
    uint8_t* dst = _sdata;
    while (dst < _edata){
        *dst++ = *src++;
    }
    
    // zero initialize .bss
    uint8_t* bss = _sbss;
    while (bss < _ebss){
        *bss++ = 0;
    }

    // // Copy the program from SD Card to SDRAM
    // volatile uint32_t *src = (volatile uint32_t *)SDCARD_BASE;
    // volatile uint32_t *dst = (volatile uint32_t *)SDRAM_BASE;
    // uint32_t words_to_copy = APP_SIZE / 4;
    
    // for (uint32_t i = 0; i < words_to_copy; i++) {
    //     dst[i] = src[i];
    // }

    // // Jump to program entry
    // ((void (*)(void))PROG_ENTRY)();

    // Draw a picture ot the frame buffer and then spin forever
    volatile uint8_t *fb_addr = (volatile uint8_t *)0x30000000;

    for (int x = 0; x < 320; x++) {
        for (int y = 0; y < 200; y++) {
            if (x < 107) {
                if (y < 100) {
                    *fb_addr = 178; // #EF0000
                } else {
                    *fb_addr = 193; // #E7E7FF
                }
            } else if (x < 213) {
                if (y < 100) {
                    *fb_addr = 198; // #5353FF
                } else {
                    *fb_addr = 173; // #FF5F5F
                }
            } else {
                if (y < 100) {
                    *fb_addr = 160; // #FFFF73
                } else {
                    *fb_addr = 116; // #5BBF4F
                }
            }

            fb_addr += 1;
        }
    }

    while (1) {}
}