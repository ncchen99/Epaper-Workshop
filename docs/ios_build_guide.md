# iOS Build 指南 📱

本文件說明如何從 Flutter 專案編譯並導出 iOS 的 IPA 檔案。

## 🛠️ 前置準備

1.  **macOS 設備**：必須使用 Mac 進行編譯。
2.  **已安裝 Flutter SDK**：請參考 [Flutter 官網](https://docs.flutter.dev/get-started/install/macos)。
3.  **已安裝 Xcode**：建議使用最新穩定版本。
4.  **CocoaPods**：若專案包含原生插件，需安裝 `pod`。

---

## 🚀 編譯步驟

### 1. 環境檢查
在終端機進入 `Flutter` 目錄，確認環境是否準備就緒：
```bash
flutter doctor
```
確認 Xcode 項目顯示為綠色打勾。

### 2. 獲取依賴
確保所有套件都已正確下載：
```bash
flutter pub get
cd ios
pod install
cd ..
```

### 3. Flutter Build
執行編譯指令以生成 Xcode 所需的檔案：
```bash
flutter build ios --release --no-codesign
```
*   `--release`：生成正式發佈版本。
*   `--no-codesign`：在終端機跳過簽署步驟，稍後在 Xcode 中手動處理。

---

## 🏗️ Xcode 導出 IPA

1.  **開啟專案**：
    打開 `Flutter/ios/Runner.xcworkspace`。

2.  **設定簽署 (Signing)**：
    *   在 Xcode 左側專案導覽列點擊 `Runner`。
    *   選擇 **TARGETS > Runner**。
    *   切換到 **Signing & Capabilities** 標籤。
    *   確保已選擇正確的 **Team** 並勾選 **Automatically manage signing**。

3.  **封裝封檔 (Archive)**：
    *   在 Xcode 頂部選單選擇 **Product > Archive**。
    *   等待編譯完成後，會彈出 **Organizer** 視窗。

4.  **導出 IPA**：
    *   在 Organizer 視窗點擊右側的 **Distribute App**。
    *   根據需求選擇 **App Store Connect** (上架用) 或 **Ad Hoc / Development** (測試用)。
    *   按照引導步驟點擊「Next」，最後點擊 **Export** 即可獲取 `.ipa` 檔案。

---

## 💡 常見問題

*   **CocoaPods 沒對齊**：若 build 失敗，可嘗試 `rm -rf ios/Pods ios/Podfile.lock && cd ios && pod install`。
*   **版本號衝突**：請在 `pubspec.yaml` 中更新 `version` 欄位後再重新 build。
