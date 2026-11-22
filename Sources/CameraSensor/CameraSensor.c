#include "include/CameraSensor.h"

static int luma(const uint8_t *pixel) {
    return (29 * pixel[0] + 150 * pixel[1] + 77 * pixel[2] + 128) >> 8;
}

static uint8_t clampByte(int value) {
    return value < 0 ? 0 : value > 255 ? 255 : (uint8_t)value;
}

static uint32_t randomBits(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *state = x;
}

void NDGradeCameraFrame(uint8_t *pixels, size_t bytesPerRow, uint32_t frameSeed) {
    uint32_t state = (frameSeed * 2654435761u) | 1u;
    for (size_t y = 0; y < ND_CAMERA_HEIGHT; y += 2) {
        uint8_t *upper = pixels + y * bytesPerRow;
        uint8_t *lower = upper + bytesPerRow;
        for (size_t x = 0; x < ND_CAMERA_WIDTH; x += 2, upper += 8, lower += 8) {
            uint8_t *sites[4] = {upper, upper + 4, lower, lower + 4};
            int levels[4], blockColor[3] = {0}, blockLuma = 0;
            for (int i = 0; i < 4; ++i) {
                levels[i] = luma(sites[i]);
                blockLuma += levels[i];
                for (int c = 0; c < 3; ++c) blockColor[c] += sites[i][c];
            }
            blockLuma = (blockLuma + 2) / 4;
            for (int c = 0; c < 3; ++c) blockColor[c] = (blockColor[c] + 2) / 4 - blockLuma;

            // A shared component survives chroma subsampling and low-bitrate encoding.
            // Bright, well-exposed surfaces have much less noise than deep shadows.
            int amplitude = 3 + (255 - blockLuma) * (255 - blockLuma) / 4200;
            uint32_t bits = randomBits(&state);
            int shared = (int)(bits & 255u) - (int)((bits >> 8) & 255u);
            uint32_t fine = randomBits(&state);
            for (int i = 0; i < 4; ++i) {
                int grain = (shared + (int)(fine & 255u) - 128) * amplitude / 255;
                fine >>= 8;
                int level = (5 * levels[i] + 3 * blockLuma + 4) / 8;
                // Leave a little shadow detail and compress the brightest stops.
                int tone = 3 + (level * 250 + 127) / 255;
                if (tone > 190) tone -= (tone - 190) / 6;
                for (int c = 0; c < 3; ++c) {
                    int localColor = sites[i][c] - levels[i];
                    int chroma = (3 * blockColor[c] + localColor) * 15 / 64;
                    sites[i][c] = clampByte(tone + chroma + grain);
                }
            }
        }
    }
}
