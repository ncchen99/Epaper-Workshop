# LEGO E-Ink Camera Workshop 🧱📸

這是一個專為電子紙工作坊設計的專案，結合了 **Arduino (ESP32)** 硬體控制與 **Flutter** 行動裝置 App。使用者可以透過 Wi-Fi 在區域網路內，將手機中的照片直接傳送到電子紙螢幕上顯示。

![LEGO Style](assets/images/demo_1.png)

## 🌟 核心特色

- 🧱 **LEGO 風格介面**：採用樂高積木風格的 UI 設計，包含積木紋理、凸點（Studs）與立體陰影。
- 🔍 **自動裝置發現**：利用 mDNS (Multicast DNS) 技術，App 會自動尋找區網內的 `epaper.local` 裝置，無需手動輸入 IP。
- 📷 **多元照片來源**：支援從手機相簿選取、即時拍攝或使用預設範例照片。
- ⚡ **即時預覽與上傳**：支援透過 REST API 直接將照片上傳至 Arduino，或透過 Cloudflare R2 雲端中轉。
- 🌈 **多色電子紙支援**：針對 4 吋多色電子紙優化，內建抖動演算法 (Dithering) 提升圖像品質。

---

## 🏗️ 系統架構

1. **Arduino (Server 端)**:
   - 啟動 Wi-Fi 並註冊 mDNS 服務名為 `epaper.local`。
   - 建立非同步 Web Server (ESPAsyncWebServer)，提供照片顯示與更新的 API。
   - 接收 JPEG 圖片，進行解碼、色彩轉換與抖動處理。
   - 驅動 4.0 吋電子紙螢幕顯示結果。
   - 使用不同的 LED 燈號顏色代表目前的運作狀態。

2. **Flutter (App 端)**:
   - 掃描區域網路內的 mDNS 服務，連向電子紙裝置。
   - 提供樂高積木風格的互動介面。
   - 處理照片裁切（符合電子紙比例）與上傳。
   - 遠端控制 Arduino 切換顯示不同的插槽 (Slot)。

---

## 🚀 快速開始

### 1. 安裝依賴 (Flutter)

```bash
cd Flutter
flutter pub get
```

### 2. 執行 App

```bash
flutter run
```

### 3. 配置與調整

編輯 `lib/config.dart` 進行進階設定：

```dart
// 切換模擬模式 (true 為模擬，false 為連接實體裝置)
static const bool mockMode = false;

// 預設 Arduino URL (會被 mDNS 自動發現覆蓋)
static const String arduinoBaseUrl = 'http://epaper.local';
```

---

## 🛠️ Arduino API 參考

App 透過 REST API 與 Arduino 溝通：

| 終端點 (Endpoint) | 方法 | 說明 |
| :--- | :--- | :--- |
| `/api/show?slot={1,2,3}` | GET | 顯示已儲存在指定插槽的圖片 |
| `/api/update?slot={1,2,3}` | GET | 指令 Arduino 從雲端下載圖片並更新插槽 |
| `/api/upload?slot={1,2,3}` | POST | 直接將 JPEG 圖片上傳至指定插槽並顯示 |

---

## 💡 狀態燈號說明 (NeoPixel)

Arduino 上的 LED 會根據目前狀態變換顏色：
- 🟠 **橘色閃爍**：等待 Wi-Fi 連線
- 🟢 **綠色**：已連接 Wi-Fi / 系統就緒
- 🔵 **藍色**：正在下載或接收圖片
- 🟡 **黃色**：正在解碼圖片
- 🎨 **七彩閃爍**：正在刷新電子紙螢幕
- 🟣 **紫色**：處理完成，準備重新啟動

---

## 📁 專案結構

```
lib/
├── main.dart                 # App 入口點
├── config.dart               # 設定檔
├── theme/
│   └── lego_theme.dart       # 樂高風格設計系統
├── widgets/
│   ├── lego_card.dart        # 積木卡片
│   ├── lego_button.dart      # 動態按鈕
│   └── ...                   # 其他樂高 UI 元件
├── services/
│   ├── arduino_service.dart  # REST API 客戶端
│   ├── discovery_service.dart# mDNS 發現服務
│   └── upload_service.dart   # 雲端傳輸服務
└── screens/
    └── home_screen.dart      # 主畫面
```

---

## 📦 依賴套件

- `flutter_riverpod`: 狀態管理
- `nsd`: mDNS 裝置發現
- `dio`: HTTP 請求處理
- `image_picker`: 相機與相簿存取
- `google_fonts`: 特色字體

---

## 📄 License

MIT
