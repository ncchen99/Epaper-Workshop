# LEGO E-Ink Camera - Arduino Firmware 🤖

這是電子紙工作坊的硬體端程式碼，基於 ESP32 開發板與 PlatformIO 開發環境。

## 🔧 硬體需求

- **微控制器**: ESP32 (建議具備 PSRAM，如 ESP32-S3)
- **顯示器**: Waveshare 4.03" 7-Color E-Paper (EPD_4in0e)
- **燈號**: NeoPixel WS2812B (3 顆)
- **按鈕**: 傳統輕觸按鈕 (3 顆)

## 🛠️ 開發環境設定

本專案建議使用 **VS Code + PlatformIO** 進行開發：

1. 安裝 PlatformIO IDE 擴充功能。
2. 開啟 `Arduino` 資料夾。
3. 確保 `platformio.ini` 設定正確。

## 📝 設定 Wi-Fi

在 `src/main.cpp` 中修改以下變數：

```cpp
const char *ssid = "您的WiFi名稱";
const char *password = "您的WiFi密碼";
```

## 📡 功能說明

- **mDNS**: 裝置啟動後可透過 `http://epaper.local` 訪問。
- **Web Server**: 提供 REST API 接口接收圖片與控制命令。
- **多格式解碼**: 支援 JPG 與 PNG 圖片解碼。
- **抖動處理 (Dithering)**: 內建 Floyd-Steinberg 抖動演算法，將 24-bit 影像轉換為電子紙支援的 7 色空間。
- **電源管理**: 處理完顯示後系統會重啟或進入優化狀態。

## 🚥 LED 狀態說明

- **橘色 (Orange)**: WiFi 連線中。
- **綠色 (Green)**: 就緒，等待指令。
- **藍色 (Blue)**: 下載/接收檔案中。
- **黃色 (Yellow)**: 圖片解碼/處理中。
- **紫色 (Purple)**: 即將重新啟動。

## 🔌 API 終端點

- `GET /`: 首頁 (控制面板)
- `GET /api/show?slot=<1-3>`: 顯示指定插槽的圖片。
- `GET /api/update?slot=<1-3>`: 從雲端 URL 更新圖片。
- `POST /api/upload?slot=<1-3>`: 直接上傳圖片檔案。

---

## 🏗️ 編譯與上傳

使用 PlatformIO 核心指令：

```bash
pio run -t upload
```

或使用 VS Code PlatformIO 圖示中的 **Upload** 按鈕。
