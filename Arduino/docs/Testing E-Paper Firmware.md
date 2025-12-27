## 🔍 **測試方式：使用 Serial Monitor**

### 1. 開啟 Serial Monitor

在 PlatformIO 中，有兩種方式：

**方式 A：使用 VS Code 指令**
- 按 `Ctrl+Shift+P` 打開指令面板
- 輸入 `PlatformIO: Serial Monitor` 並選擇

**方式 B：使用終端機**
```bash
pio device monitor
```

### 2. 設定 Baud Rate

程式中設定的鮑率是 **9600**（第 505 行 `Serial.begin(9600)`），請確保 Serial Monitor 也設為 **9600 baud**。

---

## 📋 **你會看到的 Log 訊息**

根據程式碼，你應該可以看到以下輸出：

| 階段 | Log 訊息 |
|------|----------|
| WiFi 連線中 | `Connecting to WiFi...` |
| WiFi 連線成功 | `Connected to WiFi` |
| LittleFS 初始化 | `Testing LittleFS Library...` → `LittleFS Done!` |
| LittleFS 格式化 | `Formatting LittleFS...` → `LittleFS formatted successfully!` |
| 下載圖片 | `開始下載 PNG...` → `下載成功，開始寫入 LittleFS...` |
| PNG 解碼 | `DecodePNG...` → `PNG 圖片寬度: xxx` → `完成像素解碼數量...` |
| 按鈕狀態 | `1/1/1`（loop 中每次都會印出三個按鈕狀態）|

---

## 🎮 **功能測試**

| 操作 | 預期行為 |
|------|----------|
| **按按鈕 1（短按）** | 顯示圖片 1，Serial 輸出 `按鈕 1 短按 → 顯示圖片 1` |
| **按按鈕 2** | 顯示圖片 2 |
| **按按鈕 3** | 顯示圖片 3 |
| **長按按鈕 1（3 秒）** | 觸發熱更新，Serial 輸出 `========== 長按偵測到！開始熱更新... ==========` |

---

## ⚠️ **注意事項**

1. **WiFi 設定**：確保你已經把第 40-41 行的 WiFi 名稱和密碼改成你的實際設定：
   ```cpp
   const char *ssid = "你的WiFi名稱";
   const char *password = "你的WiFi密碼";
   ```

2. **雲端 URL**：確保 `CLOUD_BASE_URL` 指向的伺服器有 `test.png`、`cat.png`、`dog.png` 這三個檔案。

3. **LED 指示**：除了 Serial Monitor，你也可以觀察板子上的 **NeoPixel LED** 顏色變化來判斷程式狀態。

---

需要我幫你執行 Serial Monitor 指令嗎？或者你有其他測試需求？