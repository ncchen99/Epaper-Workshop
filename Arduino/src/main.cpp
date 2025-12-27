// 系統或外部函式庫標頭檔的引用，使用尖括號<...>，表示從 編譯器內建的標頭檔路徑
// 或 外部安裝的函式庫路徑 去找檔案。 常見於 Arduino
// Core、官方函式庫或第三方套件。
#include <Adafruit_NeoPixel.h> // Adafruit NeoPixel/WS2812 控制函式庫
#include <Arduino.h> // Arduino 核心 API（pinMode、digitalWrite、Serial 等）
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <JPEGDEC.h>  // JPEG 解碼器
#include <LittleFS.h> // 小型檔案系統，提供在快閃記憶體上的檔案讀寫
#include <WiFi.h>
#include <WiFiClientSecure.h> // 支援 HTTPS 連線
#include <pngle.h>            // 輕量 PNG 解碼器（將 PNG 轉為 RGB 資料）

// 專案函式庫標頭檔引用，使用雙引號 "..."，表示先從 專案目錄
// 搜尋，再去系統路徑找。 通常是你自己寫的程式檔案或專案內附的函式庫。
#include "DEV_Config.h" // 裝置/EPD 相關硬體設定
#include "EPD_4in0e.h"  // 4.0 吋 EPD 面板驅動程式庫
#include "dither.h"     // 圖像抖動程式庫

// 巨集定義 (Macro Definition)
// 編譯前處理器（Preprocessor）會在編譯時期，直接把這些名稱替換成指定的內容。
#define EPD_WIDTH EPD_4IN0E_WIDTH   // 將通用寬度別名到此面板的實際寬度常數
#define EPD_HEIGHT EPD_4IN0E_HEIGHT // 將通用高度別名到此面板的實際高度常數
#define LED_PIN A0  // NeoPixel 資料腳位使用 A0（會映射到實際 GPIO）
#define LED_COUNT 3 // 連接的 NeoPixel 燈珠數量為 1 顆

// 物件與全域變數宣告 (Object & Global Variable Declarations)
static File file;       // LittleFS 的檔案物件（全域）；用於開檔、讀寫等
uint8_t BRIGHTNESS = 5; // LED 亮度（0~255）；5 表示很低的亮度
Adafruit_NeoPixel
    strip(LED_COUNT,       // 建立 NeoPixel 物件：燈珠數量
          LED_PIN,         // 使用的資料腳位
          NEO_GRB          // 色序為 GRBW
              + NEO_KHZ800 // 通訊頻率 800kHz（WS2812/NeoPixel 常見規格）
    );                     // 物件建構子結尾

uint8_t epd_bitmap_canvas[EPD_WIDTH * EPD_HEIGHT / 2];
// EPD 畫布緩衝區；/2 表示每個位元組存放 2 個像素（假設 4bpp：每像素4位元）

uint8_t *png_rgb_canvas =
    (uint8_t *)ps_malloc(EPD_4IN0E_WIDTH * EPD_4IN0E_HEIGHT * 3);
// 於 PSRAM 配置 RGB888 暫存區（寬 * 高 * 3 bytes）；轉型為 uint8_t*
// 便於逐位元組操作

// ------------------ 常數設定 ------------------
// 常數不會改變
const char *ssid = "fatfat";       // 你的WiFi名稱
const char *password = "88888888"; // 你的WiFi密碼
const char btn1Pin = A1;           // 按鈕接到的腳位編號
const char btn2Pin = A2;           // 按鈕接到的腳位編號
const char btn3Pin = A3;           // 按鈕接到的腳位編號

// ------------------ 雲端 URL 設定 ------------------
// Cloudflare R2 或其他雲端儲存的 Base URL（請依實際情況修改）
const char *CLOUD_BASE_URL =
    "https://REMOVED_R2_PUBLIC_ID.r2.dev/"; // 注意結尾要有斜線
                                                            // /
// "https://REMOVED_R2_PUBLIC_ID.r2.dev/"; // 注意結尾要有斜線 /
// 三個插槽的圖片檔名（Flutter App 上傳時需覆蓋這些檔名）
const char *SLOT1_FILENAME = "test.jpg";   // 插槽 1（對應按鈕 1）
const char *SLOT2_FILENAME = "demo_1.jpg"; // 插槽 2（對應按鈕 2）
const char *SLOT3_FILENAME = "demo_2.jpg"; // 插槽 3（對應按鈕 3）

// ------------------ 變數宣告 ------------------
// 變數會改變，用來記錄狀態
bool nowBtn1State = HIGH;  // 按鈕的狀態
bool nowBtn2State = HIGH;  // 按鈕的狀態
bool nowBtn3State = HIGH;  // 按鈕的狀態
bool lastBtn1State = HIGH; // 按鈕的狀態（用來比對是否有改變）
bool lastBtn2State = HIGH; // 上一次按鈕的狀態（用來比對是否有改變）
bool lastBtn3State = HIGH; // 上一次按鈕的狀態（用來比對是否有改變）
// ------------------ 防彈跳相關變數 ------------------
// 這些使用 unsigned long (無號長整數)，因為時間是毫秒(ms)，會比 int 大很多
unsigned long lastBtn1DebounceTime = 0; // 上一次按鈕狀態改變的時間
unsigned long lastBtn2DebounceTime = 0; // 上一次按鈕狀態改變的時間
unsigned long lastBtn3DebounceTime = 0; // 上一次按鈕狀態改變的時間
unsigned long debounceDelay =
    50; // 防彈跳延遲時間 (50ms)，如果太小會有雜訊，太大會感覺按鈕延遲

// ------------------ 長按偵測相關變數 ------------------
unsigned long btn1PressStartTime = 0; // 按鈕 1 開始被按下的時間
bool btn1LongPressTriggered = false;  // 標記長按是否已觸發（避免重複觸發）
const unsigned long LONG_PRESS_DURATION = 3000; // 長按門檻時間（3000ms = 3秒）

// ------------------ API 觸發 Flag 變數 ------------------
// 避免在 AsyncWebServer callback 中執行耗時操作（會觸發 Watchdog Timer）
volatile int updateSlotObj = 0; // 標記需要更新的 slot (1-3)，0 表示無需更新
volatile int showSlotObj = 0;   // 標記需要顯示的 slot (1-3)，0 表示無需顯示

//------------------------ LED 控制函式 ------------------------------//
// 這個函式用來控制板子上的 NeoPixel LED 顯示顏色
// H = 色相 (Hue)，S = 飽和度 (Saturation)，B = 亮度 (Brightness)
void LED(uint16_t N, uint16_t H, uint8_t S, uint8_t B) {
  // 設定第 N 顆 LED 的顏色（存在記憶體裡）
  strip.setPixelColor(N, strip.ColorHSV(H * 256, S, B));
  // 把設定好的顏色真的「送出去」顯示
  strip.show();
}

//------------------------ PNG 解碼相關變數 ------------------------------//
// 這些是用來處理 PNG 圖片的全域變數
pngle_t *pngle;                       // PNGle 函式庫的主要物件（負責解碼 PNG）
static uint32_t totalPixelCount = 0;  // 記錄總共處理了多少像素
static uint32_t packedPixelCount = 0; // 記錄壓縮後寫入 EPD 緩衝的像素數量
static uint8_t pixelPairIndex = 0;    // 目前在處理「兩個像素一組」中的第幾個
static uint8_t firstPixelColorCode = 0;  // 暫存第一個像素的顏色代碼
static uint8_t secondPixelColorCode = 0; // 暫存第二個像素的顏色代碼
static uint32_t millisPNG = 0;       // 記錄開始處理 PNG 的時間（用來算耗時）
static volatile bool failed = false; // 標記是否發生 PSRAM 記憶體不足錯誤
static uint32_t imgW = 0, imgH = 0;

//------------------------ PNG 回調函式宣告 ------------------------------//
// 「回調函式」就是當 PNGle 在不同階段會自動呼叫的函式
void initCallback(pngle_t *pngle, uint32_t w,
                  uint32_t h); // 初始化：讀到圖片大小時呼叫
void drawCallback(pngle_t *pngle, uint32_t x, uint32_t y, uint32_t w,
                  uint32_t h, uint8_t rgba[4]); // 繪製每個像素
void doneCallback(pngle_t *pngle);              // 完成解碼時呼叫

//------------------------ 重置參數 ------------------------------//
static inline void resetDecodeState() {
  failed = false;
  totalPixelCount = 0;
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;
  millisPNG = millis();
  // 如果畫布已經分配，清零（避免上一次資料殘留）
  if (png_rgb_canvas && imgW && imgH) {
    memset(png_rgb_canvas, 0, imgW * imgH * 3);
  }
  if (epd_bitmap_canvas) {
    memset(epd_bitmap_canvas, 0, EPD_WIDTH * EPD_HEIGHT / 2);
  }
}
//------------------------ 初始化回調 ------------------------------//
void initCallback(pngle_t *pngle, uint32_t w, uint32_t h) {
  imgW = w;
  imgH = h;

  // ========== 關鍵修正：PNG 尺寸檢查防呆 ==========
  // 如果圖片尺寸不符合電子紙解析度，直接拒絕處理
  if (imgW != EPD_WIDTH || imgH != EPD_HEIGHT) {
    Serial.println("========== 錯誤：PNG 尺寸不符！ ==========");
    Serial.printf("PNG 尺寸: %ux%u\n", imgW, imgH);
    Serial.printf("EPD 尺寸: %ux%u\n", EPD_WIDTH, EPD_HEIGHT);
    Serial.println("請確保上傳的 PNG 圖片尺寸為 400x600 或 600x400");
    Serial.println("=========================================");
    failed = true; // 標記失敗
    return;        // 直接返回，不進行後續處理
  }

  // 分配/重新分配 png_rgb_canvas
  size_t need = (size_t)imgW * imgH * 3;
  if (png_rgb_canvas) {
    free(png_rgb_canvas);
    png_rgb_canvas = nullptr;
  }
  png_rgb_canvas = (uint8_t *)ps_malloc(need); // 使用 PSRAM 分配大型記憶體
  if (!png_rgb_canvas) {
    Serial.println("malloc RGB canvas fail");
    failed = true;
    return;
  }
  memset(png_rgb_canvas, 0, need);

  // 印出一些 debug 訊息
  Serial.println("開始處理 PNG 圖片");
  millisPNG = millis(); // 記錄時間
  totalPixelCount = 0;
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;

  Serial.print("PNG 圖片寬度: ");
  Serial.println(w);
  Serial.print("PNG 圖片高度: ");
  Serial.println(h);

  // 每次新圖片都重置狀態
  resetDecodeState();
}

//------------------------ 繪製回調 ------------------------------//
// 當 PNGle 解出一個像素 (x,y) 時，就會呼叫這裡
void drawCallback(pngle_t *pngle, uint32_t x, uint32_t y, uint32_t w,
                  uint32_t h, const uint8_t rgba[4]) {
  if (!png_rgb_canvas)
    return;
  // pngle 可能一次回調多個像素區塊 (w,h)，但當前像素是 (x,y) 的顏色在 rgba
  // 多數 pngle 範例是逐像素呼叫，你也可只用 (x,y) 這一點
  if (x < imgW && y < imgH) {
    size_t idx = ((size_t)y * imgW + x) * 3;
    png_rgb_canvas[idx + 0] = rgba[0];
    png_rgb_canvas[idx + 1] = rgba[1];
    png_rgb_canvas[idx + 2] = rgba[2];
    totalPixelCount++;
  } else if (!failed) {
    Serial.println("drawCallback 越界");
    failed = true;
  }
}

//------------------------ 完成回調 ------------------------------//
// 當整張 PNG 讀完時呼叫這裡
void doneCallback(pngle_t *pngle) {
  if (failed || !png_rgb_canvas)
    return;

  Serial.print("dithering..."); // 印訊息
  // 執行「抖動演算法」→ 減少顏色但讓效果看起來比較平滑
  dither(png_rgb_canvas, EPD_WIDTH, EPD_HEIGHT);

  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;

  // 將 RGB 轉 EPD 色碼並以兩像素/1Byte 打包
  const size_t pxCount = (size_t)EPD_WIDTH * EPD_HEIGHT;
  // 走訪所有像素，把 RGB 顏色轉換成電子紙支援的顏色代碼
  for (size_t i = 0; i < pxCount; ++i) {
    uint8_t r = png_rgb_canvas[i * 3 + 0];
    uint8_t g = png_rgb_canvas[i * 3 + 1];
    uint8_t b = png_rgb_canvas[i * 3 + 2];

    uint8_t code;
    if (r == 255 && g == 255 && b == 255)
      code = EPD_4IN0E_WHITE;
    else if (r == 0 && g == 0 && b == 0)
      code = EPD_4IN0E_BLACK;
    else if (r == 255 && g == 255 && b == 0)
      code = EPD_4IN0E_YELLOW;
    else if (r == 255 && g == 0 && b == 0)
      code = EPD_4IN0E_RED;
    else if (r == 0 && g == 0 && b == 255)
      code = EPD_4IN0E_BLUE;
    else if (r == 0 && g == 255 && b == 0)
      code = EPD_4IN0E_GREEN;
    else
      code = EPD_4IN0E_BLACK;

    if (pixelPairIndex == 0)
      firstPixelColorCode = code;
    else
      secondPixelColorCode = code;

    pixelPairIndex++;

    if (pixelPairIndex == 2) {
      if (packedPixelCount < pxCount / 2) {
        epd_bitmap_canvas[packedPixelCount] =
            (firstPixelColorCode << 4) | (secondPixelColorCode & 0x0F);
      }
      pixelPairIndex = 0;
      packedPixelCount++;
    }
  }

  Serial.println("完成像素解碼數量：");
  Serial.println(totalPixelCount);
  Serial.print("共耗時：");
  uint32_t el = millis() - millisPNG;
  Serial.printf("%u.%03u秒\n", el / 1000, el % 1000);
}

//------------------------ 主解碼函式 ------------------------------//
// 這個函式會打開檔案，呼叫 PNGle 解碼，最後得到 EPD 可以使用的像素資料
void PngDecodeLittleFS(const String &path) {
  Serial.println("DecodePNG...");

  File file = LittleFS.open(path, "r");
  if (!file) {
    Serial.println("open PNG fail");
    return;
  }

  pngle_t *pngle = pngle_new();
  if (!pngle) {
    Serial.println("pngle_new fail");
    file.close();
    return;
  }

  pngle_set_init_callback(pngle, initCallback);
  pngle_set_draw_callback(pngle, drawCallback);
  pngle_set_done_callback(pngle, doneCallback);

  // 可選：如需在 callback 內帶上下文，使用 pngle_set_user_data(pngle,
  // your_ptr);

  uint8_t buf[1024];
  while (file.available()) {
    size_t len = file.readBytes((char *)buf, sizeof(buf));
    int fed = pngle_feed(pngle, buf, len);
    if (fed < 0) {
      Serial.printf("pngle_feed error: %s\n", pngle_error(pngle));
      failed = true;
      break;
    }
  }
  file.close();

  pngle_destroy(pngle);
  Serial.println(failed ? "PNG 解碼失敗" : "PNG 文件解碼成功");
}

//------------------------ JPEG 解碼相關 ------------------------------//
JPEGDEC jpeg;
File jpegFile;

// JPEG 檔案開啟回調
void *jpegOpen(const char *filename, int32_t *size) {
  jpegFile = LittleFS.open(filename, "r");
  if (!jpegFile)
    return nullptr;
  *size = jpegFile.size();
  return &jpegFile;
}

// JPEG 檔案關閉回調
void jpegClose(void *handle) {
  if (jpegFile)
    jpegFile.close();
}

// JPEG 檔案讀取回調
int32_t jpegRead(JPEGFILE *handle, uint8_t *buffer, int32_t length) {
  if (!jpegFile)
    return 0;
  return jpegFile.read(buffer, length);
}

// JPEG 檔案搜尋回調
int32_t jpegSeek(JPEGFILE *handle, int32_t position) {
  if (!jpegFile)
    return 0;
  return jpegFile.seek(position);
}

// JPEG 繪製回調 - 每個 MCU (Minimum Coded Unit) 區塊
int jpegDrawCallback(JPEGDRAW *pDraw) {
  // 將 RGB565 像素轉換為 RGB888 並存入 png_rgb_canvas
  for (int y = 0; y < pDraw->iHeight; y++) {
    for (int x = 0; x < pDraw->iWidth; x++) {
      int destX = pDraw->x + x;
      int destY = pDraw->y + y;

      if (destX < EPD_WIDTH && destY < EPD_HEIGHT) {
        uint16_t pixel = pDraw->pPixels[y * pDraw->iWidth + x];
        // RGB565 轉 RGB888
        uint8_t r = ((pixel >> 11) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x3F) << 2;
        uint8_t b = (pixel & 0x1F) << 3;

        size_t idx = ((size_t)destY * EPD_WIDTH + destX) * 3;
        png_rgb_canvas[idx + 0] = r;
        png_rgb_canvas[idx + 1] = g;
        png_rgb_canvas[idx + 2] = b;
      }
    }
  }
  return 1; // 繼續解碼
}

// JPEG 主解碼函式
void JpegDecodeLittleFS(const String &path) {
  Serial.println("DecodeJPEG...");

  // 確保 RGB 畫布已分配
  if (!png_rgb_canvas) {
    png_rgb_canvas = (uint8_t *)ps_malloc(EPD_WIDTH * EPD_HEIGHT * 3);
    if (!png_rgb_canvas) {
      Serial.println("無法分配 RGB 畫布記憶體！");
      return;
    }
  }
  memset(png_rgb_canvas, 255, EPD_WIDTH * EPD_HEIGHT * 3); // 預設白色背景

  if (jpeg.open(path.c_str(), jpegOpen, jpegClose, jpegRead, jpegSeek,
                jpegDrawCallback)) {
    int imgWidth = jpeg.getWidth();
    int imgHeight = jpeg.getHeight();
    Serial.printf("JPEG 圖片: %d x %d\n", imgWidth, imgHeight);
    Serial.printf("EPD 尺寸: %d x %d\n", EPD_WIDTH, EPD_HEIGHT);
    Serial.printf("可用記憶體: Heap=%d, PSRAM=%d\n", ESP.getFreeHeap(),
                  ESP.getFreePsram());

    // 檢查圖片尺寸是否超過 EPD
    if (imgWidth > EPD_WIDTH * 2 || imgHeight > EPD_HEIGHT * 2) {
      Serial.println("警告: 圖片太大，即使縮放 1/2 也無法完全顯示！");
      Serial.println("建議使用 400x600 或更小的圖片。");
    } else if (imgWidth > EPD_WIDTH || imgHeight > EPD_HEIGHT) {
      Serial.println("注意: 圖片尺寸超過 EPD，將只顯示左上角部分。");
      Serial.println("建議使用 400x600 的圖片以獲得最佳效果。");
    }

    unsigned long startTime = millis();

    // 嘗試解碼（可選：使用縮放）
    // 縮放選項：0=原始, JPEG_SCALE_HALF, JPEG_SCALE_QUARTER, JPEG_SCALE_EIGHTH
    int options = 0;

    // 如果圖片寬或高是 EPD 的 2 倍以上，使用 1/2 縮放
    if (imgWidth >= EPD_WIDTH * 2 || imgHeight >= EPD_HEIGHT * 2) {
      options = JPEG_SCALE_HALF;
      Serial.println("使用 1/2 縮放解碼...");
    }

    Serial.println("開始解碼...");
    if (jpeg.decode(0, 0, options)) {
      Serial.printf("JPEG 解碼成功！耗時 %lu ms\n", millis() - startTime);

      // 執行抖動演算法
      Serial.println("執行抖動處理...");
      dither(png_rgb_canvas, EPD_WIDTH, EPD_HEIGHT);

      // 將 RGB 轉換為 EPD 格式
      packedPixelCount = 0;
      pixelPairIndex = 0;
      const size_t pxCount = (size_t)EPD_WIDTH * EPD_HEIGHT;

      for (size_t i = 0; i < pxCount; ++i) {
        uint8_t r = png_rgb_canvas[i * 3 + 0];
        uint8_t g = png_rgb_canvas[i * 3 + 1];
        uint8_t b = png_rgb_canvas[i * 3 + 2];

        uint8_t code;
        if (r == 255 && g == 255 && b == 255)
          code = EPD_4IN0E_WHITE;
        else if (r == 0 && g == 0 && b == 0)
          code = EPD_4IN0E_BLACK;
        else if (r == 255 && g == 255 && b == 0)
          code = EPD_4IN0E_YELLOW;
        else if (r == 255 && g == 0 && b == 0)
          code = EPD_4IN0E_RED;
        else if (r == 0 && g == 0 && b == 255)
          code = EPD_4IN0E_BLUE;
        else if (r == 0 && g == 255 && b == 0)
          code = EPD_4IN0E_GREEN;
        else
          code = EPD_4IN0E_BLACK;

        if (pixelPairIndex == 0)
          firstPixelColorCode = code;
        else
          secondPixelColorCode = code;

        pixelPairIndex++;

        if (pixelPairIndex == 2) {
          if (packedPixelCount < pxCount / 2) {
            epd_bitmap_canvas[packedPixelCount] =
                (firstPixelColorCode << 4) | (secondPixelColorCode & 0x0F);
          }
          pixelPairIndex = 0;
          packedPixelCount++;
        }
      }
      Serial.println("JPEG 處理完成！");
    } else {
      Serial.println("JPEG 解碼失敗！");
      Serial.printf("錯誤代碼: %d\n", jpeg.getLastError());
      Serial.println("可能原因：");
      Serial.println("  1. 圖片格式不支援");
      Serial.println("  2. 圖片損壞");
      Serial.println("  3. 記憶體不足");
      Serial.println("建議：使用標準基線式 JPEG 格式，尺寸 400x600");
    }
    jpeg.close();
  } else {
    Serial.println("無法開啟 JPEG 檔案！");
    Serial.println("請確認檔案存在且格式正確。");
  }
}
//------------------------ 下載圖片函式 ------------------------------//
// 功能：從指定的 URL 下載圖片，並存到 LittleFS (ESP32 的快閃檔案系統)
// 使用與 example 相同的簡單方法：http.begin(_url) + http.writeToStream(&file)
void download_PNG_Url(String _url, String _target) {
  Serial.println("開始下載圖片...");
  Serial.println("URL: " + _url);

  // 檢查 WiFi 連線狀態
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("錯誤: WiFi 未連線！");
    return;
  }

  const int maxRetries = 3;
  int retryCount = 0;
  bool downloadSuccess = false;
  bool writeSuccess = false;

  // ------------------ 主下載重試迴圈 ------------------ //
  while (retryCount < maxRetries) {
    HTTPClient http;

    // ========== 關鍵修正 ==========
    // 直接使用 http.begin(_url)，與 example 版本完全一致
    // 這樣 HTTPClient 會自己處理 HTTPS 連線
    http.begin(_url);
    http.setTimeout(30000); // 30 秒逾時

    Serial.println("發送 GET 請求...");
    int httpCode = http.GET();

    Serial.printf("HTTP 回應碼: %d\n", httpCode);

    if (httpCode == HTTP_CODE_OK) {
      Serial.println("下載成功，開始寫入 LittleFS...");
      downloadSuccess = true;

      // 刪除舊檔案
      if (LittleFS.exists(_target)) {
        if (LittleFS.remove(_target)) {
          Serial.println("舊檔案已成功刪除");
        } else {
          Serial.println("舊檔案刪除失敗");
        }
      }

      // ------------------ 檔案寫入 ------------------ //
      int writeRetryCount = 0;
      while (writeRetryCount < maxRetries) {
        Serial.println("嘗試寫入檔案：" + _target);
        File file = LittleFS.open(_target, FILE_WRITE);
        if (!file) {
          Serial.println("無法開啟檔案進行寫入...");
          writeRetryCount++;
          delay(100);
          continue;
        }

        // 使用 writeToStream 直接寫入（與 example 一致的方式）
        int writtenBytes = http.writeToStream(&file);

        if (writtenBytes > 0) {
          Serial.println("檔案寫入成功");
          Serial.printf("寫入大小: %d 字節\n", writtenBytes);
          file.close();

          // 驗證檔案大小
          File verifyFile = LittleFS.open(_target, FILE_READ);
          if (verifyFile) {
            Serial.printf("驗證檔案大小: %d 字節\n", verifyFile.size());
            if (verifyFile.size() > 0) {
              writeSuccess = true;
            }
            verifyFile.close();
          }
          break;
        } else {
          Serial.println("檔案寫入失敗，重試中...");
          file.close();
          writeRetryCount++;
          delay(100);
        }
      }

      if (writeSuccess) {
        http.end();
        break;
      }
    } else {
      Serial.printf("下載失敗, HTTP 代碼: %d\n", httpCode);
      if (httpCode < 0) {
        Serial.println("可能原因：網路問題或 SSL 連線失敗");
      }
    }

    http.end();
    retryCount++;
    Serial.printf("重試次數: %d/%d\n", retryCount, maxRetries);
    delay(1000);
  }

  // ------------------ 結果檢查 ------------------ //
  if (!downloadSuccess) {
    Serial.println("下載失敗，請檢查網路或 URL！");
  } else if (!writeSuccess) {
    Serial.println("檔案寫入失敗，請檢查 LittleFS 空間！");
  } else {
    Serial.println("圖片下載並儲存成功！");
  }

  delay(100);
}
//--------------------------------------------
// 儲存陣列到檔案
// 功能：把 epd_bitmap_canvas 的內容分段寫入 LittleFS
void SaveArray(String _pngid) {
  Serial.println("SaveArray 開始執行，目標檔案: " + _pngid);
  Serial.flush();

  // 開啟檔案（寫入模式）
  File file = LittleFS.open(_pngid, FILE_WRITE);
  if (!file) {
    Serial.println("檔案開啟失敗！");
    return;
  }

  // 確認資料是否存在
  if (sizeof(epd_bitmap_canvas) == 0) {
    Serial.println("沒有資料可寫入！（大小為 0）");
    file.close();
    return;
  }

  size_t totalSize = sizeof(epd_bitmap_canvas);
  Serial.printf("準備寫入 %d 位元組...\n", totalSize);
  Serial.flush();

  // 使用較大的 chunk 以減少寫入次數
  const size_t chunkSize = 4096; // 每次寫入 4KB
  size_t totalBytesWritten = 0;

  // 分段寫入檔案
  for (size_t i = 0; i < totalSize; i += chunkSize) {
    size_t bytesToWrite = min(chunkSize, totalSize - i);
    size_t bytesWritten = file.write(epd_bitmap_canvas + i, bytesToWrite);

    if (bytesWritten != bytesToWrite) {
      Serial.println("分段寫入檔案失敗！");
      break;
    }

    totalBytesWritten += bytesWritten;

    // 每次寫入後讓出 CPU
    yield();
    delay(1);
  }

  // 確認是否寫入完整
  if (totalBytesWritten == totalSize) {
    Serial.println("資料已全部成功寫入檔案，檔案大小：" + (String)file.size());
  } else {
    Serial.printf("寫入總共 %d 位元組，但預期應為 %d 位元組\n",
                  totalBytesWritten, totalSize);
  }

  file.close();
  Serial.println("SaveArray 完成");
}

//--------------------------------------------
// 從檔案讀取陣列
// 功能：把 LittleFS 裡的檔案內容讀入 epd_bitmap_canvas
void GetArray(String _pngid) {
  Serial.println("嘗試讀取檔案 :" + (String)_pngid);

  // 開啟檔案（讀取模式）
  File file = LittleFS.open((String)_pngid, FILE_READ);
  if (!file) {
    Serial.println("檔案開啟失敗！");
    return;
  }

  // 取得檔案大小
  size_t fileSize = file.size();

  // 如果檔案比緩衝區大 → 只讀取能容納的部分
  if (fileSize > sizeof(epd_bitmap_canvas)) {
    fileSize = sizeof(epd_bitmap_canvas);
    Serial.println("檔案大小超過緩衝區，將截斷多餘資料！");
  }
  // 如果檔案比緩衝區小 → 先清空緩衝區，剩下的補 0
  else if (fileSize < sizeof(epd_bitmap_canvas)) {
    Serial.println("檔案比預期小，剩餘部分將填 0");
    memset(epd_bitmap_canvas, 0, sizeof(epd_bitmap_canvas));
  }

  // 把檔案內容讀到陣列中
  size_t bytesRead = file.readBytes((char *)epd_bitmap_canvas, fileSize);

  Serial.printf("成功讀取 %d 位元組資料\n", bytesRead);

  file.close(); // 關閉檔案
}

//------------------------ 顯示圖片函式 ------------------------------//
bool showImage(int slot) {
  String filename = "/" + String(slot) + ".bin";
  Serial.println("Showing image from " + filename);

  // Check if file exists before trying to read it
  if (!LittleFS.exists(filename)) {
    Serial.println("Error: File " + filename + " does not exist!");
    Serial.println("Please update the slot first using /api/update?slot=" +
                   String(slot));
    return false;
  }

  LED(slot - 1, 92, 255, BRIGHTNESS);
  GetArray(filename);
  LED(slot - 1, 192, 255, BRIGHTNESS);

  Serial.println("正在刷新電子紙顯示器...");
  unsigned long startTime = millis();
  EPD_4IN0E_Display(epd_bitmap_canvas);
  Serial.printf("電子紙刷新完成！耗時 %lu ms\n", millis() - startTime);

  LED(slot - 1, 64, 255, BRIGHTNESS);
  return true;
}

//------------------------ 更新圖片函式 ------------------------------//
void updateImage(int slot) {
  String filename;
  if (slot == 1)
    filename = SLOT1_FILENAME;
  else if (slot == 2)
    filename = SLOT2_FILENAME;
  else if (slot == 3)
    filename = SLOT3_FILENAME;
  else
    return;

  Serial.println("Updating slot " + String(slot));
  LED(slot - 1, 160, 255, BRIGHTNESS);

  // 判斷副檔名來決定下載的暫存檔名和解碼方式
  String lowerFilename = filename;
  lowerFilename.toLowerCase();
  bool isJpeg =
      lowerFilename.endsWith(".jpg") || lowerFilename.endsWith(".jpeg");
  String tempFile = isJpeg ? "/temp.jpg" : "/temp.png";

  download_PNG_Url(String(CLOUD_BASE_URL) + filename, tempFile);
  LED(slot - 1, 192, 255, BRIGHTNESS);

  // 根據格式選擇解碼器
  if (isJpeg) {
    Serial.println("使用 JPEG 解碼器...");
    JpegDecodeLittleFS(tempFile);
  } else {
    Serial.println("使用 PNG 解碼器...");
    PngDecodeLittleFS(tempFile);
  }

  Serial.println("解碼完成，直接顯示圖片...");
  LED(slot - 1, 64, 255, BRIGHTNESS);

  // 先直接顯示已解碼的資料（不需要從檔案讀取）
  Serial.println("正在刷新電子紙顯示器...");
  unsigned long startTime = millis();
  EPD_4IN0E_Display(epd_bitmap_canvas);
  Serial.printf("電子紙刷新完成！耗時 %lu ms\n", millis() - startTime);

  // 顯示完成後，嘗試儲存到檔案（供下次快速讀取）
  Serial.println("準備儲存陣列到檔案...");
  SaveArray("/" + String(slot) + ".bin");
  Serial.println("updateImage 完成！");
}

//------------------------ WebServer (REST API) ------------------------------//
AsyncWebServer server(80);

const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE HTML><html>
<head>
  <title>E-Paper Control</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
  body { font-family: Arial; text-align: center; margin:0px auto; padding-top: 30px; background-color: #f4f4f4; }
  .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
  button { padding: 15px 30px; font-size: 18px; margin: 10px; cursor: pointer; border: none; border-radius: 5px; color: white; width: 100%; max-width: 300px; }
  .btn-1 { background-color: #e74c3c; }
  .btn-2 { background-color: #2ecc71; }
  .btn-3 { background-color: #3498db; }
  .btn-update { background-color: #f39c12; }
  h1 { color: #333; }
  #status { font-weight: bold; color: #666; }
  </style>
</head>
<body>
<div class="container">
  <h1>E-Paper Workshop</h1>
  <p>Status: <span id="status">Ready</span></p>
  <p><button class="btn-1" onclick="trigger('/api/show?slot=1')">Show Cat (Slot 1)</button></p>
  <p><button class="btn-2" onclick="trigger('/api/show?slot=2')">Show Dog (Slot 2)</button></p>
  <p><button class="btn-3" onclick="trigger('/api/show?slot=3')">Show Others (Slot 3)</button></p>
  <hr>
  <p><button class="btn-update" onclick="trigger('/api/update?slot=1')">Update Slot 1 & Show</button></p>
</div>
<script>
  function trigger(url) {
    document.getElementById('status').innerHTML = "Sending...";
    document.getElementById('status').style.color = "orange";
    
    fetch(url)
      .then(response => {
        if (response.ok) {
           document.getElementById('status').innerHTML = "Success";
           document.getElementById('status').style.color = "green";
        } else {
           document.getElementById('status').innerHTML = "Error";
           document.getElementById('status').style.color = "red";
        }
        setTimeout(() => {
            document.getElementById('status').innerHTML = "Ready";
            document.getElementById('status').style.color = "#666";
        }, 2000);
      })
      .catch(error => {
        console.error('Error:', error);
        document.getElementById('status').innerHTML = "Fail";
        document.getElementById('status').style.color = "red";
      });
  }
</script>
</body>
</html>
)rawliteral";

// ------------------ 主啟動程序 ------------------
// Arduino 的 setup()：只會在開機或重置時執行一次
void setup() {
  Serial.begin(
      9600); // 啟動序列埠，設定鮑率 9600（讓我們可以在 Serial Monitor 印資料）

  strip.begin();   // 初始化 NeoPixel 物件（準備好控制 LED）
  LED(0, 0, 0, 0); // 把 LED 關掉（H=0, S=0, B=0 → 沒顏色）
  LED(1, 0, 0, 0); // 把 LED 關掉（H=0, S=0, B=0 → 沒顏色）
  LED(2, 0, 0, 0); // 把 LED 關掉（H=0, S=0, B=0 → 沒顏色）
  delay(1000);     // 等待 1 秒

  WiFi.begin(ssid, password); // 啟動wifi

  while (WiFi.status() != WL_CONNECTED) // 等待wif連線
  {
    LED(0, 32, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「等待wif連線」
    LED(1, 32, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「等待wif連線」
    LED(2, 32, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「等待wif連線」
    delay(1000);
    Serial.println("Connecting to WiFi...");
  }
  Serial.println("Connected to WiFi");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  if (MDNS.begin("epaper")) {
    Serial.println("MDNS responder started");
    Serial.println("You can access this device at: http://epaper.local");
    // 廣播 HTTP 服務
    MDNS.addService("http", "tcp", 80);
  } else {
    Serial.println("Error setting up MDNS responder!");
    Serial.println("Please use IP address instead: http://" +
                   WiFi.localIP().toString());
  }

  // Init REST API Endpoints

  // ========== 關鍵修正：使用 Flag 機制避免在 Callback 中執行耗時操作
  // ========== API: Show Image GET /api/show?slot=<1|2|3>
  server.on("/api/show", HTTP_GET, [](AsyncWebServerRequest *request) {
    if (request->hasParam("slot")) {
      int slot = request->getParam("slot")->value().toInt();
      if (slot >= 1 && slot <= 3) {
        // 不直接執行，而是設定 Flag，讓 loop() 去執行
        showSlotObj = slot;
        request->send(200, "text/plain", "Show request queued");
        Serial.printf("API: 收到顯示請求 - Slot %d\n", slot);
      } else {
        request->send(400, "text/plain", "Invalid Slot");
      }
    } else {
      request->send(400, "text/plain", "Missing Slot");
    }
  });

  // API: Update Image
  // GET /api/update?slot=<1|2|3>
  server.on("/api/update", HTTP_GET, [](AsyncWebServerRequest *request) {
    if (request->hasParam("slot")) {
      int slot = request->getParam("slot")->value().toInt();
      if (slot >= 1 && slot <= 3) {
        // 不直接執行，而是設定 Flag，讓 loop() 去執行
        updateSlotObj = slot;
        request->send(200, "text/plain", "Update request queued");
        Serial.printf("API: 收到更新請求 - Slot %d\n", slot);
      } else {
        request->send(400, "text/plain", "Invalid Slot");
      }
    } else {
      request->send(400, "text/plain", "Missing Slot");
    }
  });

  // API: Direct Upload Image (POST with multipart/form-data)
  // POST /api/upload?slot=<1|2|3>
  // Body: multipart form with 'image' field containing JPEG data
  server.on(
      "/api/upload", HTTP_POST,
      // onRequest callback - called after upload complete
      [](AsyncWebServerRequest *request) {
        if (!request->hasParam("slot")) {
          request->send(400, "text/plain", "Missing Slot");
          return;
        }
        int slot = request->getParam("slot")->value().toInt();
        if (slot < 1 || slot > 3) {
          request->send(400, "text/plain", "Invalid Slot");
          return;
        }
        // 觸發顯示（上傳的檔案已經在 onUpload 時存好了）
        showSlotObj = slot;
        request->send(200, "text/plain", "Upload complete, displaying...");
        Serial.printf("API: 上傳完成 - Slot %d\n", slot);
      },
      // onUpload callback - handle file upload
      [](AsyncWebServerRequest *request, String filename, size_t index,
         uint8_t *data, size_t len, bool final) {
        static File uploadFile;
        static String tempPath;

        if (!request->hasParam("slot"))
          return;
        int slot = request->getParam("slot")->value().toInt();
        if (slot < 1 || slot > 3)
          return;

        tempPath = "/temp_upload.jpg";

        if (index == 0) {
          // First chunk - open file
          Serial.printf("Upload Start: %s (slot %d)\n", filename.c_str(), slot);
          LED(slot - 1, 160, 255, BRIGHTNESS);

          // 刪除舊的暫存檔
          if (LittleFS.exists(tempPath)) {
            LittleFS.remove(tempPath);
          }
          uploadFile = LittleFS.open(tempPath, FILE_WRITE);
          if (!uploadFile) {
            Serial.println("Failed to open file for writing");
            return;
          }
        }

        // Write data chunk
        if (uploadFile && len > 0) {
          uploadFile.write(data, len);
        }

        if (final) {
          // Last chunk - close file and process
          if (uploadFile) {
            uploadFile.close();
          }
          Serial.printf("Upload Complete: %d bytes\n", index + len);
          LED(slot - 1, 192, 255, BRIGHTNESS);

          // 解碼 JPEG 並準備顯示
          JpegDecodeLittleFS(tempPath);

          // 存檔為 bin 供下次快速讀取
          String binPath = "/" + String(slot) + ".bin";
          SaveArray(binPath);
          Serial.println("Image saved to " + binPath);

          // 清理暫存檔
          LittleFS.remove(tempPath);
          LED(slot - 1, 64, 255, BRIGHTNESS);
        }
      });

  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send_P(200, "text/html", index_html);
  });
  server.begin();

  LED(0, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」
  LED(1, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」
  LED(2, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」

  LED(0, 16, 255,
      BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  LED(1, 16, 255,
      BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  LED(2, 16, 255,
      BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  Serial.println("\nTesting LittleFS Library...\n");
  while (!LittleFS.begin(
      true)) // 嘗試啟動 LittleFS 檔案系統（存在 ESP32 的快閃記憶體上）
  {
    LED(0, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
    LED(1, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
    LED(2, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
    delay(200);                 // 再等 1 秒
    LED(0, 0, 255, 0);          // 讓 LED 2 關掉（亮度=0）
    LED(1, 0, 255, 0);          // 讓 LED 2 關掉（亮度=0）
    LED(2, 0, 255, 0);          // 讓 LED 2 關掉（亮度=0）
    delay(200);                 // 再等 1 秒
    Serial.println("\nLittleFS Fail...\n");
  }
  Serial.println("\nLittleFS Done!\n"); // 成功啟動檔案系統
  LED(0, 32, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  LED(1, 32, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  LED(2, 32, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」

  Serial.println("Formatting LittleFS...");
  if (LittleFS.format()) // 格式化檔案系統，清空檔案
  {
    Serial.println("LittleFS formatted successfully!");
    LED(0, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
    LED(1, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
    LED(2, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  } else {
    Serial.println("LittleFS format failed!");
    LED(0, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
    LED(1, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
    LED(2, 0, 255, BRIGHTNESS); // LED 2 亮起另一個顏色，表示「檔案系統失敗」
  }

  // 在 PSRAM 分配一塊 RGB 畫布，大小 = 寬 * 高 * 3 bytes (R,G,B)
  png_rgb_canvas = (uint8_t *)ps_malloc(EPD_4IN0E_WIDTH * EPD_4IN0E_HEIGHT * 3);

  // 清空 EPD 畫布緩衝區（全部填 0）
  memset(epd_bitmap_canvas, 0x00, EPD_WIDTH * EPD_HEIGHT / 2);

  // 設置PIN腳
  pinMode(btn1Pin, INPUT);
  pinMode(btn2Pin, INPUT);
  pinMode(btn3Pin, INPUT);

  // // 建立一個簡單的測試圖案（7 個不同的填充樣式）
  // uint8_t pattern[] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66};
  // int block_height = EPD_HEIGHT / 7; // 每個區塊的高度（把畫面分成 7 塊）
  // int bytes_per_row = EPD_WIDTH / 2; // 每行需要多少 bytes（1 byte = 2
  // 像素，因為是 4bpp）

  // // 逐行填充圖案
  // for (int y = 0; y < EPD_HEIGHT; y++)
  // {
  //   int block_index = y / block_height; // 判斷目前是哪一個區塊
  //   if (block_index > 6)
  //     block_index = 6;                    // 避免最後一行超出範圍
  //   uint8_t value = pattern[block_index]; // 該區塊要填的數值

  //   for (int x = 0; x < bytes_per_row; x++)
  //   {
  //     int index = y * bytes_per_row + x; // 計算在緩衝區中的位置
  //     epd_bitmap_canvas[index] = value;  // 填入圖案數值
  //   }
  // }

  LED(0, 32, 255, BRIGHTNESS); // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  LED(1, 32, 255, BRIGHTNESS); // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  LED(2, 32, 255, BRIGHTNESS); // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  DEV_Module_Init();           // 初始化開發板相關模組（SPI, GPIO 等）
  EPD_4IN0E_Init();            // 初始化電子紙顯示器
  EPD_4IN0E_Clear(EPD_4IN0E_WHITE); // 如果要先清除畫面，可以打開這行
  LED(0, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」
  LED(1, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」
  LED(2, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」

  // 自動下載功能已停用 - 改用 API 或按鈕手動觸發下載
  // 如需在開機時自動下載，請取消以下註解：

  /*
  // 輔助函式：根據副檔名選擇解碼器
  auto decodeImage = [](const char* filename, const String& tempFile) {
    String lowerFilename = String(filename);
    lowerFilename.toLowerCase();
    if (lowerFilename.endsWith(".jpg") || lowerFilename.endsWith(".jpeg")) {
      JpegDecodeLittleFS(tempFile);
    } else {
      PngDecodeLittleFS(tempFile);
    }
  };

  // 下載 Slot 1
  LED(0, 160, 255, BRIGHTNESS);
  String slot1Lower = String(SLOT1_FILENAME); slot1Lower.toLowerCase();
  String tempFile1 = (slot1Lower.endsWith(".jpg") ||
  slot1Lower.endsWith(".jpeg")) ? "/temp.jpg" : "/temp.png";
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT1_FILENAME, tempFile1);
  LED(0, 192, 255, BRIGHTNESS);
  decodeImage(SLOT1_FILENAME, tempFile1);
  SaveArray("/1.bin");
  LED(0, 64, 255, BRIGHTNESS);

  // 下載 Slot 2
  LED(1, 160, 255, BRIGHTNESS);
  String slot2Lower = String(SLOT2_FILENAME); slot2Lower.toLowerCase();
  String tempFile2 = (slot2Lower.endsWith(".jpg") ||
  slot2Lower.endsWith(".jpeg")) ? "/temp.jpg" : "/temp.png";
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT2_FILENAME, tempFile2);
  LED(1, 192, 255, BRIGHTNESS);
  decodeImage(SLOT2_FILENAME, tempFile2);
  SaveArray("/2.bin");
  LED(1, 64, 255, BRIGHTNESS);

  // 下載 Slot 3
  LED(2, 160, 255, BRIGHTNESS);
  String slot3Lower = String(SLOT3_FILENAME); slot3Lower.toLowerCase();
  String tempFile3 = (slot3Lower.endsWith(".jpg") ||
  slot3Lower.endsWith(".jpeg")) ? "/temp.jpg" : "/temp.png";
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT3_FILENAME, tempFile3);
  LED(2, 192, 255, BRIGHTNESS);
  decodeImage(SLOT3_FILENAME, tempFile3);
  SaveArray("/3.bin");
  LED(2, 64, 255, BRIGHTNESS);
  */

  Serial.println("Setup 完成！");
  Serial.println("使用 API 或按鈕來下載和顯示圖片：");
  Serial.println("  - API: http://10.85.182.1/api/update?slot=1");
  Serial.println("  - 按鈕: 短按顯示，長按 3 秒更新");
}

// ------------------ 主循環 ------------------
// Arduino 的 loop()：會不斷重複執行
void loop() {
  // ========== 關鍵修正：在主迴圈中處理 API 觸發的請求 ==========
  // 檢查是否有待處理的更新請求（來自 API）
  if (updateSlotObj > 0) {
    int slot = updateSlotObj;
    updateSlotObj = 0; // 立即重置，避免重複執行
    Serial.printf("執行更新請求 - Slot %d\n", slot);
    updateImage(slot);
    Serial.println("更新完成！");
  }

  // 檢查是否有待處理的顯示請求（來自 API）
  if (showSlotObj > 0) {
    int slot = showSlotObj;
    showSlotObj = 0; // 立即重置，避免重複執行
    Serial.printf("執行顯示請求 - Slot %d\n", slot);
    bool success = showImage(slot);
    if (!success) {
      Serial.println("顯示失敗：檔案不存在，請先更新 Slot");
    }
  }

  // 讀取按鈕的當前狀態
  bool Btn1Value = digitalRead(btn1Pin);
  bool Btn2Value = digitalRead(btn2Pin);
  bool Btn3Value = digitalRead(btn3Pin);
  // Serial.println((String)Btn1Value + "/" + (String)Btn2Value + "/" +
  //  (String)Btn3Value);

  // ESP32 的 mDNS 會自動在背景運行，不需要手動 update

  // ------------------ 按鈕1處理（含長按偵測）------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn1Value != lastBtn1State) {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn1DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn1DebounceTime) > debounceDelay) {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn1Value != nowBtn1State) {
      nowBtn1State = Btn1Value;

      if (nowBtn1State == LOW) {
        // 按鈕剛被按下 → 記錄按下的起始時間
        btn1PressStartTime = millis();
        btn1LongPressTriggered = false; // 重置長按觸發標記
      } else {
        // 按鈕剛放開 → 如果不是長按，則執行「短按」功能（顯示圖片）
        if (!btn1LongPressTriggered) {
          Serial.println("按鈕 1 短按 → 顯示圖片 1");
          showImage(1);
        }
        btn1LongPressTriggered = false; // 重置長按標記
      }
    }

    // 長按偵測：按鈕持續被按住時檢查是否超過 3 秒
    if (nowBtn1State == LOW && !btn1LongPressTriggered) {
      if ((millis() - btn1PressStartTime) >= LONG_PRESS_DURATION) {
        btn1LongPressTriggered = true; // 標記已觸發，避免重複執行
        Serial.println("========== 長按偵測到！開始熱更新... ==========");

        // 閃爍 LED 表示開始熱更新
        for (int i = 0; i < 3; i++) {
          LED(0, 0, 255, BRIGHTNESS);
          LED(1, 0, 255, BRIGHTNESS);
          LED(2, 0, 255, BRIGHTNESS);
          delay(100);
          LED(0, 0, 0, 0);
          LED(1, 0, 0, 0);
          LED(2, 0, 0, 0);
          delay(100);
        }

        // 執行熱更新：重新下載第 1 張圖片
        updateImage(1);

        Serial.println("========== 熱更新完成！ ==========");
      }
    }
  }

  // ------------------ 按鈕2處理 ------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn2Value != lastBtn2State) {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn2DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn2DebounceTime) > debounceDelay) {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn2Value != nowBtn2State) {
      nowBtn2State = Btn2Value;
      // 如果按鈕是 HIGH（被按下去）
      if (nowBtn2State == LOW) {
        // TODO：這裡可以加上要做的事情（例如切換 LED 狀態）
        showImage(2);
      }
    }
  }

  // ------------------ 按鈕3處理 ------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn3Value != lastBtn3State) {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn3DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn3DebounceTime) > debounceDelay) {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn3Value != nowBtn3State) {
      nowBtn3State = Btn3Value;
      // 如果按鈕是 HIGH（被按下去）
      if (nowBtn3State == LOW) {
        // TODO：這裡可以加上要做的事情（例如切換 LED 狀態）
        showImage(3);
      }
    }
  }

  // ------------------ 更新狀態 ------------------
  // 把現在的按鈕狀態存起來，下一次 loop() 執行時會用來比對
  lastBtn1State = Btn1Value;
  lastBtn2State = Btn2Value;
  lastBtn3State = Btn3Value;
}
