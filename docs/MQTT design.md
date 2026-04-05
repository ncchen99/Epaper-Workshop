# 系統架構與實作規格書：分散式多裝置 E-Paper 控制系統

## 1. 專案概述
本專案旨在開發一套高彈性、低延遲的 E-Paper 顯示控制系統。系統架構採用 MQTT 協定，將「圖形處理/雲端存儲」與「終端硬體顯示」解耦。為適應專案發展週期，實作將分為兩個階段：第一階段專注於區域網路內的精準單機控制（Desktop 電腦作為 Broker）；第二階段則擴展為基於公有雲的商業化架構（支援多對多裝置綁定）。

> **架構設計原則：** 兩個階段採用完全相同的 Topic 結構與裝置綁定機制，唯一差異為 Broker 的部署位置。因此從階段一遷移至階段二時，Flutter App 與 ESP32 Firmware 的程式碼幾乎無需修改，僅需變更 Broker 連線位址即可。

---

## 2. 子專案構成

本專案由兩個需開發的子專案，以及一份 Broker 部署設定文件構成：

1. **Flutter App**（手機控制端）
2. **ESP32 Firmware**（Arduino 端）
3. **Broker 部署設定文件**（非開發項目，記錄安裝與設定步驟）

> **說明：** MQTT Broker（Mosquitto）本身已實作完整的 Topic 路由邏輯，無需額外開發。當 ESP32 訂閱 `devices/{MAC}/cmd` 後，Mosquitto 會自動將訊息僅轉發給對應的裝置，不需為 Broker 撰寫任何程式碼。

---

## 3. 第一階段：Demo 階段（高機動區域網路模式）

**目標：** 在無外部網際網路依賴的環境下（例如校園大地遊戲、展覽現場），透過區域網路精準控制每一塊電子紙的畫面更新。

### 3.1 角色與網路拓樸
* **網路環境：** 封閉式區域網路（Local Wi-Fi），所有裝置須連接至同一 AP。
* **MQTT Broker：** 部署於 **Desktop 電腦端**（直接於作業系統上安裝並啟動 Mosquitto）。
* **MQTT Clients：** 手機 App（控制端）、所有 ESP32-S3 電子紙裝置（接收端）。

### 3.2 Broker 部署方式
Desktop 環境不受行動平台沙盒限制，可直接安裝原生 MQTT Broker：

* **Windows / macOS / Linux：** 安裝 [Mosquitto](https://mosquitto.org/)，啟動後即於背景持續監聽 TCP Port `1883`。
* **確認 IP：** 在 Desktop 上執行 `ipconfig`（Windows）或 `ifconfig` / `ip a`（macOS/Linux）取得區網 IP（例如 `192.168.1.100`），供手機與 ESP32-S3 設定連線位址使用。
* **防火牆：** 確保作業系統防火牆允許 Port `1883` 的 TCP 入站連線。

### 3.3 Topic 設計與通訊邏輯
採用與第二階段**完全相同**的 MAC address 私有路由，確保每塊電子紙可被單獨控制，並保證未來遷移至雲端時程式碼相容。

* **裝置指令主題：** `devices/{MAC_Address}/cmd`
  * **說明：** 手機向此主題發布圖片 URL 或更新指令；對應 MAC 的 ESP32-S3 訂閱此主題接收指令。
* **裝置狀態回報主題（選配但建議）：** `devices/{MAC_Address}/state`
  * **說明：** ESP32-S3 完成圖片下載或發生錯誤時，向此主題發布狀態；手機 App 訂閱此主題以顯示「更新成功/失敗」的 UI 提示。

### 3.4 裝置綁定機制
與第二階段相同，透過 MAC address 建立手機與特定硬體的關聯：

1. **硬體識別：** ESP32-S3 開機時讀取自身 MAC 位址（例如 `AA:BB:CC:11:22:33`）。
2. **視覺化呈現：** 將 MAC 位址顯示於 E-Paper 螢幕（純文字或 QR Code）。
3. **App 綁定：** 使用者於手機 App 輸入 MAC 位址或掃描 QR Code，完成綁定後記錄於本地。

### 3.5 核心運作流程（Workflow）
1. **環境建立：** Desktop 啟動 Mosquitto Broker。手機與 ESP32-S3 連接至同一區域網路，以 Desktop 的區網 IP 作為 Broker 位址進行連線。ESP32-S3 連線後訂閱 `devices/{自身MAC}/cmd`。
2. **圖片處理：** 使用者透過手機 App 選擇或拍攝圖片，App 將圖片上傳至 Cloudflare R2，取得公開存取網址（URL）。
3. **發送指令：** 手機 App 選擇目標裝置，將含有 R2 URL 的 JSON 訊息發布至 `devices/{目標MAC}/cmd`。
4. **畫面更新：** Mosquitto 僅將訊息轉發給對應的 ESP32-S3，該裝置下載圖片並刷新 E-Paper 畫面，其他裝置不受影響。

---

## 4. 第二階段：商用測試階段（雲端分散式部署模式）

**目標：** 打破實體網路限制，實現跨網域的設備控制，為商業化量產做準備。

### 4.1 角色與網路拓樸
* **網路環境：** 網際網路（Internet）。手機與裝置可處於完全不同的網路環境（例如手機用 5G，裝置用家用 Wi-Fi）。
* **MQTT Broker：** 遷移至**公有雲服務**（例如 HiveMQ、EMQX，或自行部署於 Google Cloud 的伺服器）。
* **MQTT Clients：** 手機 App、各地的 ESP32-S3 電子紙裝置。

### 4.2 與第一階段的差異

| | 第一階段 | 第二階段 |
|---|---|---|
| Broker 位置 | 本地 Desktop | 公有雲 |
| Topic 結構 | `devices/{MAC}/cmd` | `devices/{MAC}/cmd`（相同）|
| 裝置綁定 | 本地記錄 | 雲端資料庫 |
| 網路範圍 | 區域網路 | 網際網路 |
| 程式碼變更 | — | 僅修改 Broker 連線位址 |

### 4.3 Topic 設計（與第一階段相同）
* **裝置指令主題：** `devices/{MAC_Address}/cmd`
* **裝置狀態回報主題（選配但建議）：** `devices/{MAC_Address}/state`

### 4.4 核心運作流程（Workflow）
1. **獨立連線：** 手機與 ESP32-S3 各自連上網際網路，並連線至公有雲 MQTT Broker。
2. **獨立訂閱：** ESP32-S3 僅訂閱專屬於自己的主題 `devices/{自身MAC}/cmd`。
3. **針對性發布：** 使用者在 App 中選擇目標裝置，App 將圖片上傳至 Cloudflare R2，取得 URL 後發布至 `devices/{目標MAC}/cmd`。
4. **精準更新：** 雲端 Broker 僅將訊息轉發給對應的 ESP32-S3，其他裝置不受影響。

---

## 5. 目錄結構參考

```text
/my_epaper_project
│
├── /flutter_app                        # 子專案一：手機控制端
│   └── /lib
│       ├── /mqtt_client                # 連線、發布、訂閱（Broker 位址可切換）
│       ├── /cloudflare_r2              # 圖片上傳與 URL 獲取
│       └── /screens                    # 裝置綁定 UI、QR Code 掃描
│
├── /esp32_firmware                     # 子專案二：Arduino 端
│   └── /src
│       ├── main.cpp
│       ├── mqtt_handler.cpp            # 連線與 Topic 訂閱邏輯
│       ├── image_downloader.cpp        # 解析 URL 並從 R2 下載圖片
│       └── e_paper_driver.cpp          # UC8253 驅動與畫面渲染
│
└── /broker_setup                       # Broker 部署設定文件（非開發項目）
    ├── README.md                       # 安裝步驟、防火牆設定說明
    └── mosquitto.conf                  # Mosquitto 設定檔範本
```