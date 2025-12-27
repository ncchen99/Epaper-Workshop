/*****************************************************************************
* | File      	:   DEV_Config.h
* | Author      :   Waveshare team
* | Function    :   Hardware underlying interface
* | Info        :
*----------------
* |	This version:   V1.0
* | Date        :   2020-02-19
* | Info        :
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documnetation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to  whom the Software is
# furished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
******************************************************************************/
#ifndef _DEV_CONFIG_H_
#define _DEV_CONFIG_H_

#include <Arduino.h>
#include <stdint.h>
#include <stdio.h>
#include <SPI.h>

/**
 * data
 **/
#define UBYTE uint8_t
#define UWORD uint16_t
#define UDOUBLE uint32_t

/**
 * GPIO config
 **/
// S3_origin
// #define EPD_SCK_PIN 36  // SCL
// #define EPD_MOSI_PIN 35 // SDA
// #define EPD_CS_PIN 34
// #define EPD_RST_PIN 41
// #define EPD_DC_PIN 40
// #define EPD_BUSY_PIN 42
// S3
// #define EPD_SCK_PIN 36  // SCL
// #define EPD_MOSI_PIN 35 // SDA
// #define EPD_CS_PIN 39
// #define EPD_RST_PIN 41
// #define EPD_DC_PIN 40
// #define EPD_BUSY_PIN 42
// nano
// #define EPD_SCK_PIN D13  // 36  // SCL
// #define EPD_MOSI_PIN D11 // 35 // SDA
// #define EPD_CS_PIN D10   // 39
// #define EPD_RST_PIN D6   // 41
// #define EPD_DC_PIN D7    // 40
// #define EPD_BUSY_PIN D5  // 42
#define EPD_SCK_PIN D13  // GPIO13（OK）
#define EPD_MOSI_PIN D11 // GPIO11（OK）
#define EPD_CS_PIN D10   // GPIO9（建議替代 D10）
#define EPD_RST_PIN D6   // GPIO3
#define EPD_DC_PIN D7    // GPIO2
#define EPD_BUSY_PIN D5  // GPIO5（OK）
// S1
//  #define EPD_SCK_PIN 14  // SCL
//  #define EPD_MOSI_PIN 12 // SDA
//  #define EPD_CS_PIN 15
//  #define EPD_RST_PIN 16
//  #define EPD_DC_PIN 4
//  #define EPD_BUSY_PIN 17

// #define EPD_SCK_PIN     13
// #define EPD_MOSI_PIN    11
// #define EPD_CS_PIN      10
// #define EPD_DC_PIN      9
// #define EPD_RST_PIN     8
// #define EPD_BUSY_PIN    7
// #define EPD_PWR_PIN     6

// #define GPIO_PIN_SET 1
// #define GPIO_PIN_RESET 0

/**
 * GPIO read and write
 **/
#define DEV_Digital_Write(_pin, _value) digitalWrite(_pin, _value == 0 ? LOW : HIGH)
#define DEV_Digital_Read(_pin) digitalRead(_pin)

/**
 * delay x ms
 **/
#define DEV_Delay_ms(__xms) delay(__xms)

/*------------------------------------------------------------------------------------------------------*/
UBYTE DEV_Module_Init(void);
void DEV_GPIO_Init(void);
void DEV_SPI_Init(void);

void GPIO_Mode(UWORD GPIO_Pin, uint8_t Mode);
void DEV_SPI_WriteByte(UBYTE data);
void DEV_SPI_SendByte(UBYTE data);
UBYTE DEV_SPI_ReadByte();
void DEV_SPI_Write_nByte(UBYTE *pData, UDOUBLE len);
void DEV_Module_Exit(void);
#endif
