# LEGO E-Ink Camera Workshop 🧱📸

這是一個整合了 **Arduino (ESP32)** 與 **Flutter** 的開源專案，旨在提供一個有趣的電子紙工作坊體驗。參與者可以透過自己組裝的硬體與手機 App，實現即時的照片傳輸與電子紙顯示。

## 📂 專案組成

本專案分為兩個主要部分：

### 1. [Arduino](./Arduino) 
- 基於 ESP32 開發板與 4.0 吋多色電子紙。
- 負責建立區域網路伺服器與 mDNS (epaper.local) 發現服務。
- 處理圖片解碼、抖動處理 (Dithering) 與螢幕驅動。
- 支援 REST API 接收圖片。

### 2. [Flutter](./Flutter)
- 提供樂高 (LEGO) 風格的行動裝置 App。
- 自動在區網內尋找電子紙裝置。
- 支援從相機、相簿選取照片，並裁切成適合電子紙的比例 (400x600)。
- 透過 REST API 遠端控制硬體。

## 🏗️ 工作流程

1. **硬體端** 啟動後連上 Wi-Fi，並在網路上廣播自己為 `epaper.local`。
2. **App 端** 開啟後自動掃描到硬體裝置。
3. 使用者在 App 中選擇照片並按下「傳送」。
4. 照片透過 Wi-Fi 傳輸至硬體端。
5. 硬體端接收照片後進行解碼並刷新電子紙螢幕。

## 🚀 快速開始

詳細的安裝與設定步驟請參考各目錄下的 `README.md`：
- [Arduino 設定說明](./Arduino/README.md)
- [Flutter App 設定說明](./Flutter/README.md)
- [iOS Build 指南](./docs/ios_build_guide.md)

---

## 🛠️ 技術棧

- **Hardware**: ESP32, 4.0" E-Ink, NeoPixel LED.
- **Software**: PlatformIO (Arduino), Flutter, mDNS, REST API.
- **Design**: LEGO-inspired components with custom shadows and textures.

## 📄 License

MIT
