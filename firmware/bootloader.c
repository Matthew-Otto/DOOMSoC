#include <stdint.h>
#include <stddef.h>

#define SET_BIT(REG, BIT)     ((REG) |= (BIT))
#define CLEAR_BIT(REG, BIT)   ((REG) &= ~(BIT))
#define READ_BIT(REG, BIT)    ((REG) & (BIT))

// Linker aliases
extern uint8_t _sidata[];
extern uint8_t _sdata[];
extern uint8_t _edata[];
extern uint8_t _sbss[];
extern uint8_t _ebss[];

void bootloader(void) __attribute__((used));

// Address Map
#define SDCARD_BASE 0x40000000
#define SDRAM_BASE  0x80000000
#define APP_SIZE    0x00010000 // BOZO

typedef struct {
    uint32_t csr;              // 0x0000
    uint8_t spi_reg;           // 0x0004
    uint8_t __pad1[3];
    uint32_t blk_addr;         // 0x0008
    uint8_t __pad2[0x400-12];
    uint32_t buffer1[0x200/4]; // 0x400
    uint32_t buffer2[0x200/4]; // 0x600
} sdcard_map;
_Static_assert(offsetof(sdcard_map, buffer1) == 0x400, "SD card buffer address offset is incorrect");

#define INIT_CLK      1U << 0
#define CLR_CS        1U << 1
#define SET_CS        1U << 2
#define WRITE_BLK     1U << 3
#define READ_BLK      1U << 4
#define SPI_BUSY      1U << 8
#define SUCCESS       1U << 9
#define ERROR         1U << 10

volatile sdcard_map* const sdcard = (volatile sdcard_map *)SDCARD_BASE;



void __attribute__((naked, section(".boot"))) _start(void) {
    __asm("la sp, __stack_top");
    __asm("j bootloader");
}


uint8_t spi_transfer(uint8_t data) {
    sdcard->spi_reg = data;
    while (READ_BIT(sdcard->csr, SPI_BUSY));
    return sdcard->spi_reg;
}


uint8_t sd_send_command(uint8_t cmd, uint32_t arg, uint8_t crc) {
    // Send a dummy byte to ensure the card is ready
    spi_transfer(0xFF);
    
    // Send the 6-byte command packet
    spi_transfer(cmd | 0x40);          // Command index + Start bits
    spi_transfer((arg >> 24) & 0xFF);  // Argument [31:24]
    spi_transfer((arg >> 16) & 0xFF);  // Argument [23:16]
    spi_transfer((arg >> 8)  & 0xFF);  // Argument [15:8]
    spi_transfer(arg & 0xFF);          // Argument [7:0]
    spi_transfer(crc);                 // CRC + Stop bit
    
    // Poll for the response (Valid responses are 0x00 to 0x7F)
    // The MSB is always 0 in a valid R1 response.
    uint8_t response;
    for (int timeout = 20; timeout > 0; timeout--) {
        response = spi_transfer(0xFF);
        if (!(response & 0x80))
            break;
    }
    
    return response;
}


int init_sdcard() {
    uint8_t r1;

    // Wake up card
    SET_BIT(sdcard->csr, INIT_CLK | CLR_CS);
    for (int i = 0; i < 10; i++) {
        spi_transfer(0xFF); // send >= 74 idle clocks
    }

    // Enter SPI Mode (CMD0)
    SET_BIT(sdcard->csr, SET_CS);
    r1 = sd_send_command(0, 0x00000000, 0x95); // send CMD0
    if (r1 != 0x01) return -1;

    // Check Voltage (CMD8)
    r1 = sd_send_command(8, 0x000001AA, 0x87); // send CMD8
    if (r1 == 0x01) {
        // Read the rest of the R7 response
        spi_transfer(0xFF);
        spi_transfer(0xFF);
        spi_transfer(0xFF);
        uint8_t r7_4 = spi_transfer(0xFF);
        
        if (r7_4 != 0xAA) return -1; // Voltage mismatch
    } else {
        return -1;
    }

    // Initialize Memory (ACMD41 Loop)
    for (int timeout = 10000; timeout > 0; timeout--) {
        // Send CMD55 (App Cmd prefix)
        sd_send_command(55, 0x00000000, 0x65);
        // Send ACMD41 with HCS (High Capacity Support) bit set
        r1 = sd_send_command(41, 0x40000000, 0x77);

        if (r1 != 0x01)
            break;
    }

    if (r1 == 0x01) return -1;

    // Increase clock speed
    CLEAR_BIT(sdcard->csr, INIT_CLK);

    // Set Block Size to 512 Bytes (CMD16)
    r1 = sd_send_command(16, 512, 0x15);
    if (r1 != 0x00) return -1;
    
    // Set CS high in-between transfers
    SET_BIT(sdcard->csr, SET_CS);

    return 0;
}

void __attribute__((noreturn, used)) bootloader(void) {
    // Copy .data section from ROM to RAM
    uint8_t* src = _sidata;
    uint8_t* dst = _sdata;
    while (dst < _edata) *dst++ = *src++;
    
    // Zero initialize .bss
    uint8_t* bss = _sbss;
    while (bss < _ebss) *bss++ = 0;

    // Initialize SD Card
    init_sdcard();

    // Copy data to SDRAM
    volatile uint32_t* dram = (volatile uint32_t *)SDRAM_BASE;

    for (int blk = 0; blk < APP_SIZE/512; blk++) {
        sdcard->blk_addr = blk;
        SET_BIT(sdcard->csr, READ_BLK);

        // wait for transfer to complete
        while (READ_BIT(sdcard->csr, SPI_BUSY));

        // copy data from SD buffer to DRAM
        for (int i = 0; i < 512/4; i++) {
            *dram++ = sdcard->buffer1[i];
        }
    }

    /// BOZO handle SD card init errors (return -1)

    // Jump to program entry
    // BOZO TODO

    while (1) {};
}
