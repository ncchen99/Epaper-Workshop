### 系統整合架構圖

1. **Flutter App:** 用戶選圖 -> 裁切 -> **上傳**至 Cloudfair R2 (覆蓋舊圖)。
2. **Cloudfair R2:** 儲存圖片 (扮演中繼站角色)。
3. **Arduino 積木:** 連網 -> **下載** Cloudfair R2 上的圖片 -> 顯示。

基於你提供的這份 Arduino 程式碼（它目前的邏輯是「開機時下載固定網址的圖片」），我為你整理這兩端的整合規格書。

---

### 第一份：Arduino 韌體規格書 (IoT Client 端)

**專案名稱：** E-Ink Modular Brick - Cloud Client Version
**功能：** 開機自動從雲端同步最新畫面，並支援離線切換。

#### 1. 網路與資源配置

* **Wi-Fi 設定:** Station Mode (需設定 SSID / Password)。
* **雲端來源 (Endpoint):**
* 插槽 1 圖片來源: `.../test.png` (App 上傳時需覆蓋此檔名)
* 插槽 2 圖片來源: `.../cat.png`
* 插槽 3 圖片來源: `.../dog.png`


* **更新邏輯:**
* **冷啟動 (Cold Boot):** 每次開機 (Setup) 時，強制重新下載這三張圖。
* **熱更新 (Hot Reload):** (建議修改) 雖然目前程式碼只在 `setup()` 下載，但將「下載流程」綁定到某個組合鍵 (例如長按按鈕 1)，這樣不用重開機也能抓新圖。



#### 2. 為了配合 Flutter 的必要修改

目前的程式碼是寫死的 URL。為了讓 App 能控制積木顯示什麼，我們約定一個**「檔案覆蓋協定」**：

* 當 App 用戶想改變「按鈕 1」的圖案時，App 必須上傳圖片並命名為 `test.png`，覆蓋掉雲端原本的那張。
* Arduino 下次開機（或刷新）時，就會抓到這張新的 `test.png`。

---

### 第二份：Flutter 應用端規格書 (Cloud Uploader 端)

**專案名稱：** E-Ink Brick Studio - Cloud Edition
**核心任務：** 將處理好的圖片上傳至 Cloudfair R2，並確保 Arduino 能讀取到正確的格式。

#### 1. 技術需求 (Technical Requirements)

* **Cloudfair R2 SDK:** 使用 `cloudfair_r2` 或透過 REST API 上傳。
* **圖片處理:**
* **格式:** 嚴格限制為 **PNG** (因為 Arduino 端用 `pngle` 解碼)。
* **解析度:** **400x600 px** (必須精準，否則 Arduino 端 `initCallback` 會報錯或顯示亂碼)。
* **色深:** 24-bit RGB (建議移除 Alpha 通道或設為不透明)。



#### 2. UI 流程與功能 (User Stories)

**畫面一：積木管理 (Dashboard)**

* 顯示三個「虛擬插槽 (Slots)」，分別對應積木上的實體按鈕 1, 2, 3。
* **Slot 1 (test.png):** 顯示目前設定的圖片預覽。
* **Slot 2 (cat.png):** 顯示目前設定的圖片預覽。
* **Slot 3 (dog.png):** 顯示目前設定的圖片預覽。

**畫面二：圖片編輯與上傳 (Editor)**

* **動作：** 用戶點擊 "Slot 1"。
* **選圖/裁切：** 選擇照片並裁切為 2:3 比例。
* **上傳 (Upload):**
* App 將圖片轉檔並重新命名為 `test.png`。
* 發送 HTTP PUT/POST 請求至 Cloudfair R2。
* **關鍵提示：** 上傳成功後，彈出視窗提示：「**上傳成功！請重新啟動積木，或按下積木的刷新鍵以同步畫面。**」



#### 3. Flutter 程式碼邏輯範例 (Cloudfair R2 Upload)

這段程式碼展示如何將圖片上傳並覆蓋指定的檔案（例如 `test.png`），這樣 Arduino 下載時就會拿到新圖。

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

class AzureService {
  // 這是 Azure Blob 的 SAS Url (Shared Access Signature)，比較安全，不用把 Key 放在 App 裡
  // 實際開發時，建議由後端 API 發放這個 URL，或者先用 Public Container 測試
  final String _containerUrl = "https://epaperupload.azurewebsites.net/Blobs/DownloadWorkShopImage";
  
  // 上傳圖片至指定插槽
  // slotName 傳入 "test.png", "cat.png", 或 "dog.png"
  Future<void> uploadImageToSlot(File imageFile, String fileName) async {
    // 建構上傳 URL (Azure Blob 使用 PUT 來上傳/覆蓋)
    // 如果你有 SAS Token，要加在 URL 後面
    String uploadUrl = "$_containerUrl/$fileName?sp=rw&..."; 

    try {
      // 讀取圖片 Bytes
      List<int> imageBytes = await imageFile.readAsBytes();

      // 使用 Dio 發送 PUT 請求
      final dio = Dio();
      await dio.put(
        uploadUrl,
        data: Stream.fromIterable(imageBytes.map((e) => [e])),
        options: Options(
          headers: {
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": "image/png", // 告訴 Azure 這是 PNG
          },
        ),
      );
      print("上傳成功: $fileName");
    } catch (e) {
      print("上傳失敗: $e");
      throw Exception("Azure Upload Failed");
    }
  }
}

```

---

### 總結建議：如何讓這個整合更順暢？

你目前的 Arduino 程式碼是在 `setup()` (開機時) 下載圖片。這意味著 App 上傳新圖後，使用者必須**「拔掉電池再重插」**或是按一下開發板上的 Reset 鍵，積木才會變更畫面。

**為了更好的體驗，建議在 Arduino 的 `loop()` 中加入一個「強制更新」的機制：**

例如：**「同時按下按鈕 1 和按鈕 3」** 時，執行重新下載的流程。

修改 Arduino `loop()` 的建議邏輯：

```cpp
void loop() {
  // ... (原本的按鈕讀取) ...

  // 新增：手動更新模式 (例如長按按鈕1，或者組合鍵)
  if (digitalRead(btn1Pin) == LOW && digitalRead(btn3Pin) == LOW) {
      Serial.println("強制更新模式啟動！");
      
      // 亮起藍燈提示連網中
      LED(0, 32, 255, BRIGHTNESS); 
      LED(1, 32, 255, BRIGHTNESS);
      LED(2, 32, 255, BRIGHTNESS);

      // 重新連線 WiFi (如果斷線的話)
      if (WiFi.status() != WL_CONNECTED) {
          WiFi.begin(ssid, password);
          while (WiFi.status() != WL_CONNECTED) delay(500);
      }

      // 重新執行下載流程
      download_PNG_Url(".../test.png", "/temp.png");
      PngDecodeLittleFS("/temp.png");
      SaveArray("/1.bin");
      
      // ... 重複下載其他張 ...

      Serial.println("更新完成！");
      LED(0, 64, 255, BRIGHTNESS); // 綠燈
      delay(1000); // 避免誤觸
  }
  
  // ...
}

```

這樣一來，你的 **Flutter App (上傳者)** 和 **Arduino 積木 (下載者)** 就完美透過雲端整合在一起了！