// Draw a spinning cube

#include <stdint.h>

// Address Map
#define SDCARD_BASE 0x40000000
#define SDRAM_BASE  0x80000000
#define FB_BASE     0x30000000

// Display Settings
#define SCREEN_W    320
#define SCREEN_H    200

// Palette (8-bit)
#define BLACK       0
#define WHITE       224

// Fixed-Point Math Constants
#define FIXED_SHIFT 8    // Equivalent to dividing/multiplying by 256
#define FOV         150  // Perspective scaling factor
#define Z_OFFSET    300  // Pushes the cube away from the camera (vertices are +/- 100)

// Linker aliases
extern uint8_t _sidata[];
extern uint8_t _sdata[];
extern uint8_t _edata[];
extern uint8_t _sbss[];
extern uint8_t _ebss[];

void bootloader(void) __attribute__((used));

void __attribute__((naked, section(".boot"))) _start(void) {
    __asm("la sp, __stack_top");
    __asm("j bootloader");
}

// Minimal absolute value helper
static inline int iabs(int v) { return v < 0 ? -v : v; }

// Write a single pixel, with bounds checking
static inline void draw_pixel(int x, int y, uint8_t color) {
    volatile uint8_t *fb = (volatile uint8_t *)FB_BASE;
    if (x >= 0 && x < SCREEN_W && y >= 0 && y < SCREEN_H) {
        fb[y * SCREEN_W + x] = color;
    }
}

// Fast clear using 32-bit writes
static void clear_screen(uint8_t color) {
    volatile uint32_t *fb = (volatile uint32_t *)FB_BASE;
    uint32_t c32 = (color << 24) | (color << 16) | (color << 8) | color;
    for (int i = 0; i < (SCREEN_W * SCREEN_H) / 4; i++) {
        fb[i] = c32;
    }
}

// Bresenham's line algorithm (already uses purely integers!)
static void draw_line(int x0, int y0, int x1, int y1, uint8_t color) {
    int dx = iabs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -iabs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy, e2;

    while (1) {
        draw_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

// 8-bit scaled Sine Lookup Table (0 to 89 degrees)
// Values are sin(angle) * 256
static const int16_t sin_lut[90] = {
      0,   4,   8,  13,  17,  22,  26,  31,  35,  40,  44,  48,  53,  57,  61,  66,  70,  74,  78,  83,
     87,  91,  95,  99, 103, 107, 111, 115, 119, 123, 127, 131, 135, 138, 142, 146, 149, 153, 156, 160,
    163, 167, 170, 173, 177, 180, 183, 186, 189, 192, 195, 198, 200, 203, 206, 208, 211, 213, 216, 218,
    220, 222, 224, 226, 228, 230, 232, 234, 235, 237, 238, 240, 241, 243, 244, 245, 246, 247, 248, 249,
    250, 251, 252, 253, 253, 254, 254, 254, 255, 255
};

// Fast integer sine function (input 0-359 degrees)
static inline int16_t fast_sin(int degree) {
    if (degree < 0) degree += 360;
    degree = degree % 360;
    
    if (degree < 90)  return sin_lut[degree];
    if (degree < 180) return sin_lut[180 - degree];
    if (degree < 270) return -sin_lut[degree - 180];
    return -sin_lut[360 - degree];
}

// Cosine is just sine shifted by 90 degrees
static inline int16_t fast_cos(int degree) {
    return fast_sin(degree + 90);
}

// Simple 3D Vector (Now strictly integer)
typedef struct {
    int x, y, z;
} Vec3;

void __attribute__((noreturn, used)) bootloader(void) {
    // Copy .data section from ROM to RAM
    uint8_t* src = _sidata;
    uint8_t* dst = _sdata;
    while (dst < _edata){
        *dst++ = *src++;
    }
    
    // Zero initialize .bss
    uint8_t* bss = _sbss;
    while (bss < _ebss){
        *bss++ = 0;
    }

    // 8 Vertices of a cube centered at origin
    // Scaled up to 100 to maintain precision before division
    Vec3 vertices[8] = {
        {-100, -100, -100}, { 100, -100, -100}, { 100,  100, -100}, {-100,  100, -100},
        {-100, -100,  100}, { 100, -100,  100}, { 100,  100,  100}, {-100,  100,  100}
    };

    // 12 Edges connecting the vertices
    int edges[12][2] = {
        {0,1}, {1,2}, {2,3}, {3,0}, // Back face
        {4,5}, {5,6}, {6,7}, {7,4}, // Front face
        {0,4}, {1,5}, {2,6}, {3,7}  // Connecting edges
    };

    // Angles are now standard integers representing degrees (0-359)
    int angle_x = 0;
    int angle_y = 0;
    int angle_z = 0;

    while (1) {
        clear_screen(BLACK);

        int projected[8][2];

        // Pre-calculate trig values for the current frame
        int cx = fast_cos(angle_x);
        int sx = fast_sin(angle_x);
        int cy = fast_cos(angle_y);
        int sy = fast_sin(angle_y);
        int cz = fast_cos(angle_z);
        int sz = fast_sin(angle_z);

        // Transform and project each vertex
        for (int i = 0; i < 8; i++) {
            int x = vertices[i].x;
            int y = vertices[i].y;
            int z = vertices[i].z;

            // X-axis rotation
            // We shift right by FIXED_SHIFT (8) to remove the 256 scaling introduced by the LUT
            int y1 = ((y * cx) - (z * sx)) >> FIXED_SHIFT;
            int z1 = ((y * sx) + (z * cx)) >> FIXED_SHIFT;

            // Y-axis rotation
            int x2 = ((x * cy) + (z1 * sy)) >> FIXED_SHIFT;
            int z2 = (-(x * sy) + (z1 * cy)) >> FIXED_SHIFT;

            // Z-axis rotation
            int x3 = ((x2 * cz) - (y1 * sz)) >> FIXED_SHIFT;
            int y3 = ((x2 * sz) + (y1 * cz)) >> FIXED_SHIFT;

            // Perspective Projection
            // Add Z_OFFSET to push it into the screen to prevent division by zero
            int z_persp = z2 + Z_OFFSET; 
            
            projected[i][0] = ((x3 * FOV) / z_persp) + (SCREEN_W / 2);
            projected[i][1] = ((y3 * FOV) / z_persp) + (SCREEN_H / 2);
        }

        // Draw the edges
        for (int i = 0; i < 12; i++) {
            draw_line(
                projected[edges[i][0]][0], projected[edges[i][0]][1],
                projected[edges[i][1]][0], projected[edges[i][1]][1],
                WHITE
            );
        }

        // Step the rotation angles (in integer degrees)
        angle_x = (angle_x + 2) % 360;
        angle_y = (angle_y + 3) % 360;
        angle_z = (angle_z + 1) % 360;

        // Busy-wait delay
        asm("wfi");
    }
}