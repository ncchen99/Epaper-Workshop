## AntiGravity Prompt（Flutter / LEGO UI / Arduino + E-Ink Demo）

> [!NOTE]
> This file is an early design prompt draft for the prototype phase.
> Some sections mention mock REST API integration, but the current production code in this repository uses MQTT.
> For current implementation, refer to `Flutter/README.md` and `docs/MQTT design.md`.

你是一位資深 Flutter 工程師 + UI 系統設計師。請建立一個 Flutter App（支援 iOS / Android），主題是「LEGO 風格遙控 Arduino E-Ink（電子紙）裝置」，Demo 情境：電子紙嵌入樂高相機套組中。請輸出**可直接編譯執行**的完整專案程式碼（含必要套件與範例資源），並依照以下規格完成。

---

# 1) App 目的與主要流程

App 用來控制遠端連線裝置的 Arduino，讓 Arduino 把圖片顯示到 E-Ink（電子紙）上。

使用者在主畫面可以：

1. 從 **兩張預設圖片**（預載入，顯示縮圖）中選一張 → 點「Send to Camera（送出到相機電子紙）」→ 上傳到 R2（Cloudflare R2）→ 取得 image URL → 透過 MQTT 發送 update 指令 → Arduino 下載並更新電子紙。
2. 點「Upload（上傳）」→ 選擇「拍照 / 從相簿選擇」→ 上傳到 R2 → 呼叫 Arduino 更新電子紙。
3. 在畫面上顯示裝置連線狀態（Connected / Disconnected / Sending / Error），並提供「重新連線」按鈕。

請先做成 **Demo 版本**：

* R2 上傳用「假資料模式 / mock service」（本地回傳假 URL），但保留正式接 R2 的程式接口與欄位（endpoint、access key、bucket、public url）。
* Arduino 控制同樣先用 mock API（回傳成功/失敗），但路由與 payload 要設計成之後可直接換成真實 API。

---

# 2) UI：LEGO 風格設計規範（必須落地成可重用元件）

整個介面要像「用樂高積木拼出來的 UI」：

## 2.1 顏色與材質

* 主要色：LEGO 紅、黃、藍、白、黑（可用 MaterialColor / ColorScheme 自定義）
* 背景：淺灰或米白（像桌面底板）
* 元件表面：像塑膠（高光 + 微陰影 + 圓角）
* 避免玻璃質感、避免 iOS blur、避免極簡扁平化

## 2.2 LEGO Stud（凸點）語彙

* 關鍵元件（卡片、按鈕、圖片選擇框）上方或邊緣要有 2~6 顆 studs（圓形凸點）
* studs 要有：上亮下暗的微立體（內陰影/高光效果）
* studs 數量依元件大小自適應

## 2.3 元件庫（請寫成 widgets + theme）

請至少做以下可復用元件（每個都要有明確參數與狀態）：

1. `LegoCard`

* 可放內容、帶 studs、圓角、塑膠高光、陰影

2. `LegoButton`

* Primary / Secondary / Danger 三種
* 按下去要有「積木被壓下」的位移動畫（scale/translate）

3. `LegoImageTile`

* 顯示預設圖片縮圖
* 選取狀態要有「樂高框」與 studs 變化

4. `LegoStatusChip`

* 顯示連線狀態（Connected/Disconnected/Sending/Error）

5. `LegoTopBar`

* 標題像印刷在積木上的字（可用 Google Font 近似：圓潤、童趣，但不要太卡通）

6. `LegoBottomSheet`

* 用來選擇「拍照 / 相簿」

所有元件必須遵循同一套 theme（圓角、陰影、studs、間距、字體），不要每個元件各做各的。

---

# 3) 主畫面佈局（必須照做）

畫面分成三區（手機直向）：

## A. Header 區

* `LegoTopBar`
* 標題：**“LEGO E-Ink Camera Controller”**
* 右側顯示 `LegoStatusChip`（連線狀態）

## B. Image Select 區

* 一個 `LegoCard` 裡面放兩張預設圖片（grid 2 columns）
* 每張圖用 `LegoImageTile`
* 預設圖片要隨專案附上兩張 demo asset（例如：簡單圖示/可愛像素圖都行）
* 選到的那張要在 UI 上明顯可見（框線、studs、陰影變化）

## C. Actions 區

* 三個按鈕（水平或垂直都可，但要像 LEGO 控制面板）

1. `Send to E-Ink`（把選到的圖片送到 Arduino）
2. `Upload Photo`（跳出 `LegoBottomSheet` 選拍照/相簿）
3. `Reconnect Device`

底部顯示 log 區（最近 5 行狀態訊息），也用 `LegoCard` 包起來。

---

# 4) 功能與資料流（要有乾淨架構）

請用乾淨的架構（例如：Riverpod / Bloc 擇一，建議 Riverpod）：

* `DeviceConnectionController`：管理連線狀態（mock）
* `ImageSelectionController`：管理選取的預設圖片與上傳圖片
* `UploadService`：上傳到 R2（先 mock，保留真實實作位置）
* `MqttService`：透過 MQTT 通知 Arduino 更新電子紙（可先 mock，保留真實實作位置）
* 狀態要可追蹤：idle / uploading / sending / success / error

提供一個 `config.dart`：

* R2 bucket、endpoint、public base url
* MQTT broker host/port
* mockMode true/false

---

# 5) 套件建議（可以調整但需可跑）

* `flutter_riverpod`
* `image_picker`（拍照/相簿）
* `dio`（HTTP）
* `freezed` 或簡單 model 也可（可選）
* 若 studs/陰影效果需要：自訂 `CustomPainter` 或 `BoxShadow` 組合即可

---

# 6) 輸出要求（非常重要）

請輸出：

1. 完整 Flutter 專案檔案結構（lib/、assets/、pubspec.yaml）
2. 每個檔案的完整內容
3. assets 放兩張預設圖片（若無法提供真圖，請用簡單 SVG/PNG 生成方案或用純程式畫圖替代，但要確保專案能跑）
4. README：如何執行、如何切換 mockMode、未來如何接真實 R2/Arduino

---

# 7) 風格限制

* 不要做成卡通插畫風 UI，而是「樂高塑膠積木質感 UI」
* 不要使用過度擬真 3D 渲染，但要有塑膠高光與凸點立體感
* 不要用玻璃擬態（glassmorphism）
* 保持乾淨、童趣、可 demo 的產品感（像真的能拿去工作坊展示）

