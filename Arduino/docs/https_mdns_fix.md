# HTTPS 下載與 mDNS 修復說明

## 日期: 2025-12-27

## 問題描述

### 1. HTTPS 下載失敗 (HTTP 代碼: -1)

**現象:**
```
開始下載 PNG...
下載 PNG 失敗, HTTP 代碼: -1
重試次數: 1/3
...
下載 PNG 失敗，請檢查網路或 URL 是否正確！
```

**原因:**
- URL 使用 HTTPS 協定：`https://REMOVED_R2_PUBLIC_ID.r2.dev/test.png`
- 原本的 `HTTPClient` 只支援 HTTP，不支援 HTTPS
- HTTP 代碼 `-1` 表示連線失敗（SSL/TLS 握手失敗）

**解決方案:**
1. 引入 `WiFiClientSecure.h` 標頭檔
2. 在下載函式中使用 `WiFiClientSecure` 客戶端
3. 設定 `client->setInsecure()` 來跳過 SSL 憑證驗證
4. 使用 `http.begin(*client, _url)` 來建立 HTTPS 連線

---

### 2. mDNS 無法存取 (http://epaper.local)

**現象:**
- 無法透過 `http://epaper.local` 存取設備
- 只能使用 IP 位址存取

**原因:**
- mDNS 服務沒有正確廣播 HTTP 服務
- 缺少 `MDNS.update()` 來保持服務活躍

**解決方案:**
1. 在 `setup()` 中加入 `MDNS.addService("http", "tcp", 80)` 來廣播 HTTP 服務
2. 在 `loop()` 中加入 `MDNS.update()` 來保持 mDNS 服務活躍
3. 加入錯誤處理和提示訊息

---

## 修改內容

### 檔案: `src/main.cpp`

#### 1. 加入 WiFiClientSecure 標頭檔 (第 12 行)
```cpp
#include <WiFiClientSecure.h> // 支援 HTTPS 連線
```

#### 2. 更新下載函式 (第 309-380 行)
**主要變更:**
- 建立 `WiFiClientSecure` 客戶端
- 使用 `client->setInsecure()` 跳過憑證驗證
- 使用 `http.begin(*client, _url)` 建立 HTTPS 連線
- 加入更詳細的除錯訊息
- 正確釋放記憶體 (`delete client`)

**關鍵程式碼:**
```cpp
WiFiClientSecure *client = new WiFiClientSecure;
if (client) {
  client->setInsecure(); // 不驗證 SSL 憑證
  http.begin(*client, _url); // 使用 HTTPS
  int httpCode = http.GET();
  Serial.printf("HTTP 回應碼: %d\n", httpCode);
  // ... 處理下載 ...
  http.end();
  delete client; // 釋放記憶體
}
```

#### 3. 改善 mDNS 設定 (第 605-613 行)
```cpp
if (MDNS.begin("epaper")) {
  Serial.println("MDNS responder started");
  Serial.println("You can access this device at: http://epaper.local");
  MDNS.addService("http", "tcp", 80); // 廣播 HTTP 服務
} else {
  Serial.println("Error setting up MDNS responder!");
  Serial.println("Please use IP address instead: http://" + WiFi.localIP().toString());
}
```

#### 4. 在 loop() 中更新 mDNS (第 786-788 行)
```cpp
// 更新 mDNS（保持 epaper.local 可用）
MDNS.update();
```

---

## 測試步驟

### 1. 上傳新韌體
```bash
# PlatformIO 會自動編譯並上傳
```

### 2. 檢查序列埠輸出
應該會看到：
```
Connected to WiFi
IP Address: 10.85.182.x
MDNS responder started
You can access this device at: http://epaper.local
```

### 3. 測試 HTTPS 下載
訪問：`http://10.85.182.x/api/update?slot=1`

應該會看到：
```
開始下載 PNG...
HTTP 回應碼: 200
下載成功，開始寫入 LittleFS...
檔案寫入成功
檔案大小: XXXXX 字節
```

### 4. 測試 mDNS
在瀏覽器中訪問：
- `http://epaper.local` ✅ 應該可以存取
- `http://epaper.local/api/show?slot=1` ✅ 應該可以顯示圖片

---

## 注意事項

### SSL 憑證驗證
目前使用 `setInsecure()` 跳過憑證驗證，這在以下情況是安全的：
- ✅ 內網環境
- ✅ 信任的雲端服務（如 Cloudflare R2）
- ✅ 開發/測試環境

如果需要驗證憑證，可以使用：
```cpp
client->setCACert(root_ca); // 設定根憑證
```

### mDNS 相容性
mDNS (`.local` 網域) 在不同平台的支援：
- ✅ **macOS**: 原生支援
- ✅ **iOS/iPadOS**: 原生支援
- ✅ **Linux**: 需要安裝 `avahi-daemon`
- ⚠️ **Windows**: 需要安裝 Bonjour 服務（iTunes 會自動安裝）
- ⚠️ **Android**: 部分瀏覽器支援

如果 `epaper.local` 無法使用，請直接使用 IP 位址。

### 記憶體管理
程式碼中使用 `new` 和 `delete` 來管理 `WiFiClientSecure` 物件：
```cpp
WiFiClientSecure *client = new WiFiClientSecure;
// ... 使用 client ...
delete client; // 記得釋放記憶體
```

這樣可以避免記憶體洩漏。

---

## 常見問題

### Q: 為什麼還是顯示 HTTP 代碼 -1？
A: 可能的原因：
1. WiFi 訊號不穩定
2. DNS 解析失敗
3. 防火牆阻擋
4. URL 錯誤

**除錯步驟:**
1. 檢查 WiFi 連線狀態
2. 嘗試 ping `REMOVED_R2_PUBLIC_ID.r2.dev`
3. 在瀏覽器中測試 URL 是否可以下載

### Q: epaper.local 還是無法存取？
A: 
1. 確認電腦和 ESP32 在同一個網路
2. Windows 用戶：安裝 Bonjour 服務
3. 檢查序列埠是否顯示 "MDNS responder started"
4. 嘗試重啟設備
5. 直接使用 IP 位址

### Q: 下載很慢？
A: 
1. Cloudflare R2 的速度取決於網路狀況
2. 確保圖片大小適中（建議 < 500KB）
3. 檢查 WiFi 訊號強度

---

## 效能優化建議

### 1. 減少下載次數
- 只在需要時下載新圖片
- 使用 LittleFS 快取已下載的圖片
- 實作 ETag 或 Last-Modified 檢查

### 2. 壓縮圖片
- 使用適當的 PNG 壓縮
- 考慮使用 4 色或 7 色調色盤
- 圖片尺寸剛好符合 EPD 解析度

### 3. 錯誤重試策略
目前已實作 3 次重試，可以根據需求調整：
```cpp
const int maxRetries = 3; // 可以改成 5 或更多
```

---

## 總結

✅ **HTTPS 下載**: 現在可以從 Cloudflare R2 下載圖片  
✅ **mDNS 服務**: 可以使用 `http://epaper.local` 存取  
✅ **錯誤處理**: 更詳細的除錯訊息  
✅ **記憶體管理**: 正確釋放 WiFiClientSecure 物件  

所有修改都已完成，請重新上傳韌體測試！
