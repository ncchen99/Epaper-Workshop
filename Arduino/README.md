# InkSync - Arduino Firmware

本資料夾為 ESP32-S3 韌體，使用 MQTT 接收指令並控制 4.03 吋 7 色電子紙。

## 硬體需求

- 微控制器: ESP32（建議 ESP32-S3 + PSRAM）
- 顯示器: Waveshare 4.03" 7-Color E-Paper
- 指示燈: NeoPixel WS2812B x3
- 按鈕: 1 顆（目前用於顯示 MAC QR Code）

## 開發環境

建議使用 VS Code + PlatformIO：

1. 安裝 PlatformIO IDE 擴充套件。
2. 開啟 Arduino 資料夾。
3. 檢查 platformio.ini（板型、lib_deps、build_flags）。

### Serial Port 提示

- 通常不必手動設定 upload_port，PlatformIO 可自動偵測。
- 若自動偵測失敗再手動指定。

macOS 常見：
- /dev/cu.usbmodemXXXX
- /dev/cu.usbserial-XXXX

Windows 常見：
- COM3
- COM18

## 主要設定

請在 src/main.cpp 調整：

```cpp
const char *ssid = "YOUR_WIFI_SSID";
const char *password = "YOUR_WIFI_PASSWORD";
const char *MQTT_BROKER_HOSTNAME = "epaper-broker.local";
const int MQTT_PORT = 1883;
```

## 架構與功能

- MQTT 架構（已取代舊 RESTful API 模式）
- 裝置 Topic：
   - devices/{MAC}/cmd
   - devices/{MAC}/state
- 支援 JPEG/PNG 解碼與 Floyd-Steinberg dithering
- 下載 Cloudflare R2 圖片後更新電子紙
- 可把裝置 MAC 顯示在 E-Paper（文字或 QR）

## MQTT 指令格式

發布到 devices/{MAC}/cmd：

```json
{"action":"update","url":"https://example.r2.dev/image.jpg","slot":1}
```

```json
{"action":"show","slot":1}
```

```json
{"action":"clear"}
```

狀態回報（devices/{MAC}/state）範例：

```json
{"mac":"AABBCC112233","status":"success","message":"Image updated"}
```

常見 status：
- online
- queued
- downloading
- decoding
- success
- error
- busy

## LED 狀態

- 橘色: 連線中（Wi-Fi 或 Broker）
- 綠色: 就緒 / 已連線
- 藍色: 下載中
- 黃色: 解碼中
- 紫色: 流程結束或即將重啟

## 燒錄模式（Bootloader）

若遇到 Could not open port 或卡在 Connecting...，可用以下方式進入 bootloader：

1. 穩定方式
- 按住外接 B1（GPIO0）不放
- 按一下白色 Reset
- 先放 Reset，再放開 B1

2. 快速方式
- 連按兩下白色 Reset（約 0.5 秒內）

## 編譯與上傳

```bash
pio run -t upload
```

若只想編譯：

```bash
pio run
```

## 相關文件

- MQTT 設計: ../docs/MQTT design.md
- Broker 部署: ../broker_setup/README.md
