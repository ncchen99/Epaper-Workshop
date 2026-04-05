# InkSync - Flutter App

這個 App 用來控制 ESP32 電子紙裝置。

目前架構是 MQTT（非 REST API）：
- App 發布指令到 devices/{MAC}/cmd
- 裝置回報狀態到 devices/{MAC}/state
- 圖片透過 Cloudflare R2 提供 URL，讓 ESP32 下載

![LEGO Style](assets/images/demo_1.png)

## 核心功能

- LEGO 風格 UI 元件與主題
- 裝置綁定（手動輸入或掃描 MAC QR Code）
- 相機 / 相簿 / 範例圖來源
- 影像裁切與壓縮（400x600）
- 上傳 R2 後以 MQTT 下發 update 指令
- 監聽裝置狀態（queued/downloading/success/error）

## 系統流程

1. App 連線 MQTT Broker（預設 epaper-broker.local:1883）。
2. 使用者選擇目標裝置 MAC。
3. App 處理圖片並上傳 Cloudflare R2。
4. App 發送：
    - {"action":"update","url":"https://...","slot":1}
    - 或 {"action":"show","slot":1}
    - 或 {"action":"clear"}
5. 裝置回報狀態到 devices/{MAC}/state，App 即時更新 UI。

## 快速開始

1. 安裝套件

```bash
cd Flutter
flutter pub get
```

2. 建立環境檔

```bash
cp .env.example .env
```

3. 編輯 .env，填入 Cloudflare R2 參數：
- R2_ACCESS_KEY_ID
- R2_SECRET_ACCESS_KEY
- R2_ENDPOINT_URL
- R2_BUCKET_NAME
- R2_PUBLIC_URL

4. 執行 App

```bash
flutter run
```

## MQTT 設定

主要設定在 lib/config.dart：

- mqttBrokerHost（預設 epaper-broker.local）
- mqttBrokerPort（預設 1883）
- mqttMdnsLookupTimeoutSeconds
- mqttConnectTimeoutSeconds

可用 dart-define 指定備援位址：

```bash
flutter run --dart-define=MQTT_BROKER_FALLBACK_HOST=192.168.1.100
```

## Topic 與 Payload

發布 Topic：
- devices/{MAC}/cmd

訂閱 Topic：
- devices/{MAC}/state

指令 payload：

```json
{"action":"update","url":"https://your-bucket.r2.dev/image.jpg","slot":1}
```

```json
{"action":"show","slot":1}
```

```json
{"action":"clear"}
```

狀態 payload：

```json
{"mac":"AABBCC112233","status":"success","message":"Image updated"}
```

## 專案結構

```text
lib/
   main.dart
   config.dart
   models/
      mqtt_command.dart
      epaper_device.dart
   services/
      mqtt_service.dart
      r2_upload_service.dart
      image_processor_service.dart
      device_storage_service.dart
   providers/
   screens/
   widgets/
   theme/
```

## 主要依賴

- flutter_riverpod: 狀態管理
- mqtt_client: MQTT 連線
- multicast_dns: .local 解析
- dio: R2 上傳 HTTP
- flutter_dotenv: 載入 .env
- image_picker: 相機與相簿
- mobile_scanner: 掃碼綁定

## 疑難排解

1. 無法連線 broker
- 確認手機與 broker 在同一網段
- 確認 1883 已開放
- 測試 epaper-broker.local 是否可解析

2. mDNS 不穩
- 改用 fallback host（IP）
- 先用 mosquitto_sub / mosquitto_pub 驗證 broker

3. 無法上傳 R2
- 檢查 .env 是否完整
- 確認 bucket 與 public URL 可讀

## 相關文件

- Broker 部署: ../broker_setup/README.md
- Arduino 韌體: ../Arduino/README.md
- iOS 打包: ../docs/ios_build_guide.md

## License

MIT
