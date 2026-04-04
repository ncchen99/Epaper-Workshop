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

---

### 🔌 串口 (Serial Port) 設定與自動偵測

在 `platformio.ini` 檔案中，關於 `upload_port` 的設定：

> [!TIP]
> **其實通常不需要手動指定 `upload_port`**。
> 直接將 `upload_port = ...` 這一行註解掉（前面加上 `;`），PlatformIO 就會自動尋找正確的裝置路徑，這在跨平台（Mac/Windows）開發時非常方便。

#### 🍎 Mac 使用者：
1. **查看指令**：在終端機輸入 `ls /dev/cu.*`。
2. **常見路徑**：`/dev/cu.usbmodemXXXX` 或 `/dev/cu.usbserial-XXXX`。

#### 🪟 Windows 使用者：
1. **查看方式**：開啟「裝置管理員」>「連接埠 (COM & LPT)」。
2. **常見路徑**：`COM3`, `COM18` 等。

---


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

### 🚀 如何進入燒錄模式 (Bootloader Mode)

如果出現 `Could not open port` 或 `Connecting...` 無限循環，代表開發板目前處於「一般執行模式」（MAC 端會顯示長串序號，如 `/dev/cu.usbmodem3C84...`）。此時必須手動進入 **Bootloader 模式**（裝置名稱會變短，如 `/dev/cu.usbmodem1101` 或 `101`）。

**建議操作順序：**

1. **方法一：手動強制模式 (最穩定)**
   - **硬體準備：** 確保你有一個按鈕接在 **B1 (GPIO 0)** 與 **GND** 腳位之間，以及使用板子上的 **白色 Reset 按鈕**。
   - **操作步驟：**
     1. **按住** 外接的 B1 按鈕不放。
     2. **按一下** 板子上的白色 Reset 按鈕。
     3. **放開** 白色 Reset 按鈕。
     4. **放開** 外接的 B1 按鈕。
   - **結果：** 此時執行 `ls /dev/cu.*` 應該會看到出現 `usbmodem1101` (或 101)，這時即可順利上載。

2. **方法二：快速雙擊模式**
   - 快速連續按兩下板子上的 **白色 Reset 按鈕** (需在 0.5 秒內完成)。
   - **成功標誌：** 板上的 RGB LED 會呈現 **緩慢閃爍綠色呼吸燈**。
   - **注意：** 若程式處於當機或緊密迴圈狀態，此方法可能失效，請改用方法一。

*提示：上載成功後，程式會自動重新啟動。若沒有自動重啟，按一下白色 Reset 鍵即可。*

---

## 🏗️ 編譯與上傳


使用 PlatformIO 核心指令：

```bash
pio run -t upload
```

或使用 VS Code PlatformIO 圖示中的 **Upload** 按鈕。
