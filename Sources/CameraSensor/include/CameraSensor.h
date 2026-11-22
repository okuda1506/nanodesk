#ifndef NANODESK_CAMERA_SENSOR_H
#define NANODESK_CAMERA_SENSOR_H

#include <stddef.h>
#include <stdint.h>

#define ND_CAMERA_WIDTH 640
#define ND_CAMERA_HEIGHT 480
#define ND_CAMERA_FPS 30

// One opaque, full-range BGRA frame. Row padding is left untouched.
void NDGradeCameraFrame(uint8_t *pixels, size_t bytesPerRow, uint32_t frameSeed);

#endif
