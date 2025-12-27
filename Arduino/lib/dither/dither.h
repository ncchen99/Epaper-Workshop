#ifndef DITHER_H
#define DITHER_H
#include <stdint.h>
#ifdef __cplusplus
extern "C"
{
#endif
    void dither(uint8_t *data, int width, int height);
#ifdef __cplusplus
}
#endif
#endif