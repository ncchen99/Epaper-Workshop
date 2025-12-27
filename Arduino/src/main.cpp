// 系統或外部函式庫標頭檔的引用，使用尖括號<...>，表示從 編譯器內建的標頭檔路徑 或 外部安裝的函式庫路徑 去找檔案。
// 常見於 Arduino Core、官方函式庫或第三方套件。
#include <Arduino.h>           // Arduino 核心 API（pinMode、digitalWrite、Serial 等）
#include <LittleFS.h>          // 小型檔案系統，提供在快閃記憶體上的檔案讀寫
#include <Adafruit_NeoPixel.h> // Adafruit NeoPixel/WS2812 控制函式庫
#include <pngle.h>             // 輕量 PNG 解碼器（將 PNG 轉為 RGB 資料）
#include <WiFi.h>
#include <HTTPClient.h>

// 專案函式庫標頭檔引用，使用雙引號 "..."，表示先從 專案目錄 搜尋，再去系統路徑找。
// 通常是你自己寫的程式檔案或專案內附的函式庫。
#include "DEV_Config.h" // 裝置/EPD 相關硬體設定
#include "EPD_4in0e.h"  // 4.0 吋 EPD 面板驅動程式庫
#include "dither.h"     // 圖像抖動程式庫

// 巨集定義 (Macro Definition)
// 編譯前處理器（Preprocessor）會在編譯時期，直接把這些名稱替換成指定的內容。
#define EPD_WIDTH EPD_4IN0E_WIDTH   // 將通用寬度別名到此面板的實際寬度常數
#define EPD_HEIGHT EPD_4IN0E_HEIGHT // 將通用高度別名到此面板的實際高度常數
#define LED_PIN A0                  // NeoPixel 資料腳位使用 A0（會映射到實際 GPIO）
#define LED_COUNT 3                 // 連接的 NeoPixel 燈珠數量為 1 顆

// 物件與全域變數宣告 (Object & Global Variable Declarations)
static File file;                        // LittleFS 的檔案物件（全域）；用於開檔、讀寫等
uint8_t BRIGHTNESS = 5;                  // LED 亮度（0~255）；5 表示很低的亮度
Adafruit_NeoPixel strip(LED_COUNT,       // 建立 NeoPixel 物件：燈珠數量
                        LED_PIN,         // 使用的資料腳位
                        NEO_GRB          // 色序為 GRBW
                            + NEO_KHZ800 // 通訊頻率 800kHz（WS2812/NeoPixel 常見規格）
);                                       // 物件建構子結尾

uint8_t epd_bitmap_canvas[EPD_WIDTH * EPD_HEIGHT / 2];
// EPD 畫布緩衝區；/2 表示每個位元組存放 2 個像素（假設 4bpp：每像素4位元）

uint8_t *png_rgb_canvas = (uint8_t *)ps_malloc(EPD_4IN0E_WIDTH * EPD_4IN0E_HEIGHT * 3);
// 於 PSRAM 配置 RGB888 暫存區（寬 * 高 * 3 bytes）；轉型為 uint8_t* 便於逐位元組操作

// ------------------ 常數設定 ------------------
// 常數不會改變
const char *ssid = "WiFi名稱";     // 你的WiFi名稱
const char *password = "WiFi密碼"; // 你的WiFi密碼
const char btn1Pin = A1;           // 按鈕接到的腳位編號
const char btn2Pin = A2;           // 按鈕接到的腳位編號
const char btn3Pin = A3;           // 按鈕接到的腳位編號

// ------------------ 雲端 URL 設定 ------------------
// Cloudflare R2 或其他雲端儲存的 Base URL（請依實際情況修改）
const char *CLOUD_BASE_URL = "https://epaperupload.azurewebsites.net/Blobs/DownloadWorkShopImage/";
// 三個插槽的圖片檔名（Flutter App 上傳時需覆蓋這些檔名）
const char *SLOT1_FILENAME = "test.png";  // 插槽 1（對應按鈕 1）
const char *SLOT2_FILENAME = "cat.png";   // 插槽 2（對應按鈕 2）
const char *SLOT3_FILENAME = "dog.png";   // 插槽 3（對應按鈕 3）

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
unsigned long debounceDelay = 50;       // 防彈跳延遲時間 (50ms)，如果太小會有雜訊，太大會感覺按鈕延遲

// ------------------ 長按偵測相關變數 ------------------
unsigned long btn1PressStartTime = 0;   // 按鈕 1 開始被按下的時間
bool btn1LongPressTriggered = false;    // 標記長按是否已觸發（避免重複觸發）
const unsigned long LONG_PRESS_DURATION = 3000; // 長按門檻時間（3000ms = 3秒）

//------------------------ LED 控制函式 ------------------------------//
// 這個函式用來控制板子上的 NeoPixel LED 顯示顏色
// H = 色相 (Hue)，S = 飽和度 (Saturation)，B = 亮度 (Brightness)
void LED(uint16_t N, uint16_t H, uint8_t S, uint8_t B)
{
  // 設定第 N 顆 LED 的顏色（存在記憶體裡）
  strip.setPixelColor(N, strip.ColorHSV(H * 256, S, B));
  // 把設定好的顏色真的「送出去」顯示
  strip.show();
}

//------------------------ PNG 解碼相關變數 ------------------------------//
// 這些是用來處理 PNG 圖片的全域變數
pngle_t *pngle;                          // PNGle 函式庫的主要物件（負責解碼 PNG）
static uint32_t totalPixelCount = 0;     // 記錄總共處理了多少像素
static uint32_t packedPixelCount = 0;    // 記錄壓縮後寫入 EPD 緩衝的像素數量
static uint8_t pixelPairIndex = 0;       // 目前在處理「兩個像素一組」中的第幾個
static uint8_t firstPixelColorCode = 0;  // 暫存第一個像素的顏色代碼
static uint8_t secondPixelColorCode = 0; // 暫存第二個像素的顏色代碼
static uint32_t millisPNG = 0;           // 記錄開始處理 PNG 的時間（用來算耗時）
static volatile bool failed = false;     // 標記是否發生 PSRAM 記憶體不足錯誤
static uint32_t imgW = 0, imgH = 0;

//------------------------ PNG 回調函式宣告 ------------------------------//
// 「回調函式」就是當 PNGle 在不同階段會自動呼叫的函式
void initCallback(pngle_t *pngle, uint32_t w, uint32_t h);                                          // 初始化：讀到圖片大小時呼叫
void drawCallback(pngle_t *pngle, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint8_t rgba[4]); // 繪製每個像素
void doneCallback(pngle_t *pngle);                                                                  // 完成解碼時呼叫

//------------------------ 重置參數 ------------------------------//
static inline void resetDecodeState()
{
  failed = false;
  totalPixelCount = 0;
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;
  millisPNG = millis();
  // 如果畫布已經分配，清零（避免上一次資料殘留）
  if (png_rgb_canvas && imgW && imgH)
  {
    memset(png_rgb_canvas, 0, imgW * imgH * 3);
  }
  if (epd_bitmap_canvas)
  {
    memset(epd_bitmap_canvas, 0, EPD_WIDTH * EPD_HEIGHT / 2);
  }
}
//------------------------ 初始化回調 ------------------------------//
void initCallback(pngle_t *pngle, uint32_t w, uint32_t h)
{
  imgW = w;
  imgH = h;

  // 你若只顯示到固定尺寸的 EPD，這裡可以檢查/拒絕超出大小
  if (imgW != EPD_WIDTH || imgH != EPD_HEIGHT)
  {
    Serial.printf("PNG size %ux%u != EPD %ux%u\n", imgW, imgH, EPD_WIDTH, EPD_HEIGHT);
    // 視需求可以直接失敗 return
  }

  // 分配/重新分配 png_rgb_canvas
  size_t need = (size_t)imgW * imgH * 3;
  if (png_rgb_canvas)
  {
    free(png_rgb_canvas);
    png_rgb_canvas = nullptr;
  }
  png_rgb_canvas = (uint8_t *)malloc(need);
  if (!png_rgb_canvas)
  {
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
void drawCallback(pngle_t *pngle, uint32_t x, uint32_t y, uint32_t w, uint32_t h, const uint8_t rgba[4])
{
  if (!png_rgb_canvas)
    return;
  // pngle 可能一次回調多個像素區塊 (w,h)，但當前像素是 (x,y) 的顏色在 rgba
  // 多數 pngle 範例是逐像素呼叫，你也可只用 (x,y) 這一點
  if (x < imgW && y < imgH)
  {
    size_t idx = ((size_t)y * imgW + x) * 3;
    png_rgb_canvas[idx + 0] = rgba[0];
    png_rgb_canvas[idx + 1] = rgba[1];
    png_rgb_canvas[idx + 2] = rgba[2];
    totalPixelCount++;
  }
  else if (!failed)
  {
    Serial.println("drawCallback 越界");
    failed = true;
  }
}

//------------------------ 完成回調 ------------------------------//
// 當整張 PNG 讀完時呼叫這裡
void doneCallback(pngle_t *pngle)
{
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
  for (size_t i = 0; i < pxCount; ++i)
  {
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

    if (pixelPairIndex == 2)
    {
      if (packedPixelCount < pxCount / 2)
      {
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
void PngDecodeLittleFS(const String &path)
{
  Serial.println("DecodePNG...");

  File file = LittleFS.open(path, "r");
  if (!file)
  {
    Serial.println("open PNG fail");
    return;
  }

  pngle_t *pngle = pngle_new();
  if (!pngle)
  {
    Serial.println("pngle_new fail");
    file.close();
    return;
  }

  pngle_set_init_callback(pngle, initCallback);
  pngle_set_draw_callback(pngle, drawCallback);
  pngle_set_done_callback(pngle, doneCallback);

  // 可選：如需在 callback 內帶上下文，使用 pngle_set_user_data(pngle, your_ptr);

  uint8_t buf[1024];
  while (file.available())
  {
    size_t len = file.readBytes((char *)buf, sizeof(buf));
    int fed = pngle_feed(pngle, buf, len);
    if (fed < 0)
    {
      Serial.printf("pngle_feed error: %s\n", pngle_error(pngle));
      failed = true;
      break;
    }
  }
  file.close();

  pngle_destroy(pngle);
  Serial.println(failed ? "PNG 解碼失敗" : "PNG 文件解碼成功");
}

//------------------------ 下載圖片函式 ------------------------------//
// 功能：從指定的 URL 下載 PNG 圖片，並存到 LittleFS (ESP32 的快閃檔案系統)
void download_PNG_Url(String _url, String _target)
{
  Serial.println("開始下載 PNG...");

  const int maxRetries = 3;     // 最大重試次數（如果失敗會再試）
  int retryCount = 0;           // 記錄已經嘗試下載的次數
  bool downloadSuccess = false; // 標記：是否成功下載到資料
  bool writeSuccess = false;    // 標記：是否成功把資料寫入檔案

  // ------------------ 主下載重試迴圈 ------------------ //
  while (retryCount < maxRetries)
  {
    HTTPClient http;           // 建立一個 HTTPClient 物件
    http.begin(_url);          // 設定要下載的網址
    int httpCode = http.GET(); // 發送 GET 請求
    // LED(1, 32, 255, BRIGHTNESS); // LED 顯示「正在下載」

    // 如果 HTTP 回應碼 = 200 (OK)
    if (httpCode == HTTP_CODE_OK)
    {
      Serial.println("下載成功，開始寫入 LittleFS...");
      downloadSuccess = true; // 標記下載成功

      // 如果目標檔案已經存在，就刪掉它
      if (LittleFS.exists(_target))
      {
        if (LittleFS.remove(_target))
        {
          Serial.println("舊檔案已成功刪除");
        }
        else
        {
          Serial.println("舊檔案刪除失敗，可能是權限問題");
        }
      }

      // ------------------ 檔案寫入重試迴圈 ------------------ //
      int writeRetryCount = 0;
      while (writeRetryCount < maxRetries)
      {
        Serial.println("嘗試寫入檔案：" + _target);
        File file = LittleFS.open(_target, FILE_WRITE); // 開啟檔案（寫入模式）
        if (!file)
        {
          Serial.println("無法開啟檔案進行寫入...");
          writeRetryCount++;
          delay(100); // 等待一下再重試
          continue;   // 跳回重試
        }

        // 嘗試把下載的內容寫入檔案
        if (http.writeToStream(&file) > 0)
        {
          Serial.println("檔案寫入成功");
          Serial.printf("檔案大小: %d 字節\n", file.size()); // 印出檔案大小
          writeSuccess = true;
          file.close(); // 關閉檔案
          break;        // 成功 → 跳出寫入重試迴圈
        }
        else
        {
          Serial.println("檔案寫入失敗，重試中...");
          file.close();
          writeRetryCount++;
          delay(100);
        }
      }

      // 如果寫入成功 → LED 提示，並跳出整個下載重試迴圈
      if (writeSuccess)
      {
        // LED(1, 96, 255, BRIGHTNESS); // LED 換顏色，表示「檔案寫入成功」
        break;
      }
    }
    else
    {
      // 如果 HTTP 回應不是 200，表示下載失敗
      Serial.printf("下載 PNG 失敗, HTTP 代碼: %d\n", httpCode);
    }

    // 紀錄重試次數
    retryCount++;
    Serial.printf("重試次數: %d/%d\n", retryCount, maxRetries);
    delay(100); // 等待一下再重試
    http.end(); // 關閉 http 連線
  }

  // ------------------ 結果檢查 ------------------ //
  if (!downloadSuccess)
  {
    Serial.println("下載 PNG 失敗，請檢查網路或 URL 是否正確！");
  }
  else if (!writeSuccess)
  {
    Serial.println("檔案寫入失敗，請檢查 LittleFS 空間或權限！");
  }

  // 最後關掉 LED
  // LED(1, 0, 0, 0);
  delay(100);
}
//--------------------------------------------
// 儲存陣列到檔案
// 功能：把 epd_bitmap_canvas 的內容分段寫入 LittleFS
void SaveArray(String _pngid)
{
  // 開啟檔案（寫入模式）
  File file = LittleFS.open(_pngid, FILE_WRITE);
  if (!file)
  {
    Serial.println("檔案開啟失敗！");
    return;
  }

  // 確認資料是否存在
  if (sizeof(epd_bitmap_canvas) == 0)
  {
    Serial.println("沒有資料可寫入！（大小為 0）");
    file.close();
    return;
  }

  const size_t chunkSize = 1024; // 每次寫入 1024 位元組
  size_t totalBytesWritten = 0;  // 總共寫入的位元組數

  // 分段寫入檔案
  for (size_t i = 0; i < sizeof(epd_bitmap_canvas); i += chunkSize)
  {
    size_t bytesToWrite = min(chunkSize, sizeof(epd_bitmap_canvas) - i);
    size_t bytesWritten = file.write(epd_bitmap_canvas + i, bytesToWrite);

    if (bytesWritten != bytesToWrite)
    {
      Serial.println("分段寫入檔案失敗！");
      break;
    }

    totalBytesWritten += bytesWritten;
  }

  // 確認是否寫入完整
  if (totalBytesWritten == sizeof(epd_bitmap_canvas))
  {
    Serial.println("資料已全部成功寫入檔案，檔案大小：" + (String)file.size());
  }
  else
  {
    Serial.printf("寫入總共 %d 位元組，但預期應為 %d 位元組\n",
                  totalBytesWritten, sizeof(epd_bitmap_canvas));
  }

  file.close(); // 關閉檔案
}

//--------------------------------------------
// 從檔案讀取陣列
// 功能：把 LittleFS 裡的檔案內容讀入 epd_bitmap_canvas
void GetArray(String _pngid)
{
  Serial.println("嘗試讀取檔案 :" + (String)_pngid);

  // 開啟檔案（讀取模式）
  File file = LittleFS.open((String)_pngid, FILE_READ);
  if (!file)
  {
    Serial.println("檔案開啟失敗！");
    return;
  }

  // 取得檔案大小
  size_t fileSize = file.size();

  // 如果檔案比緩衝區大 → 只讀取能容納的部分
  if (fileSize > sizeof(epd_bitmap_canvas))
  {
    fileSize = sizeof(epd_bitmap_canvas);
    Serial.println("檔案大小超過緩衝區，將截斷多餘資料！");
  }
  // 如果檔案比緩衝區小 → 先清空緩衝區，剩下的補 0
  else if (fileSize < sizeof(epd_bitmap_canvas))
  {
    Serial.println("檔案比預期小，剩餘部分將填 0");
    memset(epd_bitmap_canvas, 0, sizeof(epd_bitmap_canvas));
  }

  // 把檔案內容讀到陣列中
  size_t bytesRead = file.readBytes((char *)epd_bitmap_canvas, fileSize);

  Serial.printf("成功讀取 %d 位元組資料\n", bytesRead);

  file.close(); // 關閉檔案
}

// ------------------ 主啟動程序 ------------------
// Arduino 的 setup()：只會在開機或重置時執行一次
void setup()
{
  Serial.begin(9600); // 啟動序列埠，設定鮑率 9600（讓我們可以在 Serial Monitor 印資料）

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
  LED(0, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」
  LED(1, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」
  LED(2, 64, 255, BRIGHTNESS); // LED 1 顯示顏色 → 表示「wif連線完成」

  LED(0, 16, 255, BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  LED(1, 16, 255, BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  LED(2, 16, 255, BRIGHTNESS); // 點亮 LED 2，顯示一個顏色，表示「LittleFS開始進行中」
  Serial.println("\nTesting LittleFS Library...\n");
  while (!LittleFS.begin(true)) // 嘗試啟動 LittleFS 檔案系統（存在 ESP32 的快閃記憶體上）
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
  LED(0, 32, 255, BRIGHTNESS);          // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  LED(1, 32, 255, BRIGHTNESS);          // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  LED(2, 32, 255, BRIGHTNESS);          // LED 2 顯示顏色 → 表示「成功啟動檔案系統」

  Serial.println("Formatting LittleFS...");
  if (LittleFS.format()) // 格式化檔案系統，清空檔案
  {
    Serial.println("LittleFS formatted successfully!");
    LED(0, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
    LED(1, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
    LED(2, 64, 255, BRIGHTNESS); // LED 2 顯示顏色 → 表示「成功啟動檔案系統」
  }
  else
  {
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
  // int bytes_per_row = EPD_WIDTH / 2; // 每行需要多少 bytes（1 byte = 2 像素，因為是 4bpp）

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

  LED(0, 32, 255, BRIGHTNESS);      // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  LED(1, 32, 255, BRIGHTNESS);      // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  LED(2, 32, 255, BRIGHTNESS);      // LED 顯示另一個顏色 → 表示「準備初始化電子紙」
  DEV_Module_Init();                // 初始化開發板相關模組（SPI, GPIO 等）
  EPD_4IN0E_Init();                 // 初始化電子紙顯示器
  EPD_4IN0E_Clear(EPD_4IN0E_WHITE); // 如果要先清除畫面，可以打開這行
  LED(0, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」
  LED(1, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」
  LED(2, 128, 255, BRIGHTNESS);     // LED 換顏色 → 表示「電子紙初始化完成」

  LED(0, 160, 255, BRIGHTNESS); // LED 換顏色 → 表示「開始下載」
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT1_FILENAME, "/temp.png");
  LED(0, 192, 255, BRIGHTNESS);   // LED 換顏色 → 表示「下載完成」
  PngDecodeLittleFS("/temp.png"); // 從 LittleFS 中讀取並解碼一張 PNG 圖片
  // EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
  SaveArray("/1.bin");
  LED(0, 64, 255, BRIGHTNESS); // LED 換顏色 → 表示「讀取、解碼、儲存完成」

  LED(1, 160, 255, BRIGHTNESS); // LED 換顏色 → 表示「開始下載」
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT2_FILENAME, "/temp.png");
  LED(1, 192, 255, BRIGHTNESS);   // LED 換顏色 → 表示「下載完成」
  PngDecodeLittleFS("/temp.png"); // 從 LittleFS 中讀取並解碼一張 PNG 圖片
  // EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
  SaveArray("/2.bin");
  LED(1, 64, 255, BRIGHTNESS); // LED 換顏色 → 表示「讀取、解碼、儲存完成」

  LED(2, 160, 255, BRIGHTNESS); // LED 換顏色 → 表示「開始下載」
  download_PNG_Url(String(CLOUD_BASE_URL) + SLOT3_FILENAME, "/temp.png");
  LED(2, 192, 255, BRIGHTNESS);   // LED 換顏色 → 表示「下載完成」
  PngDecodeLittleFS("/temp.png"); // 從 LittleFS 中讀取並解碼一張 PNG 圖片
  // EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
  SaveArray("/3.bin");
  LED(2, 64, 255, BRIGHTNESS); // LED 換顏色 → 表示「讀取、解碼、儲存完成」

  // PngDecodeLittleFS("/test.png"); // 從 LittleFS 中讀取並解碼一張 PNG 圖片
  // LED(2, 192, 255, BRIGHTNESS); // LED 換顏色 → 表示「PNG 解碼完成」
  // EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
  // LED(2, 64, 255, BRIGHTNESS);          // LED 顯示另一個顏色 → 表示「顯示完成」
}

// ------------------ 主循環 ------------------
// Arduino 的 loop()：會不斷重複執行
void loop()
{
  // 讀取按鈕的當前狀態
  bool Btn1Value = digitalRead(btn1Pin);
  bool Btn2Value = digitalRead(btn2Pin);
  bool Btn3Value = digitalRead(btn3Pin);
  Serial.println((String)Btn1Value + "/" + (String)Btn2Value + "/" + (String)Btn3Value);
  // ------------------ 按鈕1處理（含長按偵測）------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn1Value != lastBtn1State)
  {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn1DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn1DebounceTime) > debounceDelay)
  {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn1Value != nowBtn1State)
    {
      nowBtn1State = Btn1Value;
      
      if (nowBtn1State == LOW)
      {
        // 按鈕剛被按下 → 記錄按下的起始時間
        btn1PressStartTime = millis();
        btn1LongPressTriggered = false; // 重置長按觸發標記
      }
      else
      {
        // 按鈕剛放開 → 如果不是長按，則執行「短按」功能（顯示圖片）
        if (!btn1LongPressTriggered)
        {
          Serial.println("按鈕 1 短按 → 顯示圖片 1");
          LED(0, 92, 255, BRIGHTNESS);          // LED 換顏色 → 表示「PNG 解碼開始」
          GetArray("/1.bin");                   // 讀取圖片1 Array
          LED(0, 192, 255, BRIGHTNESS);         // LED 換顏色 → 表示「PNG 解碼完成」
          EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
          LED(0, 64, 255, BRIGHTNESS);          // LED 顯示另一個顏色 → 表示「顯示完成」
        }
        btn1LongPressTriggered = false; // 重置長按標記
      }
    }
    
    // 長按偵測：按鈕持續被按住時檢查是否超過 3 秒
    if (nowBtn1State == LOW && !btn1LongPressTriggered)
    {
      if ((millis() - btn1PressStartTime) >= LONG_PRESS_DURATION)
      {
        btn1LongPressTriggered = true; // 標記已觸發，避免重複執行
        Serial.println("========== 長按偵測到！開始熱更新... ==========");
        
        // 閃爍 LED 表示開始熱更新
        for (int i = 0; i < 3; i++)
        {
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
        Serial.println("開始重新下載插槽 1 的圖片...");
        LED(0, 160, 255, BRIGHTNESS); // LED 換顏色 → 表示「開始下載」
        download_PNG_Url(String(CLOUD_BASE_URL) + SLOT1_FILENAME, "/temp.png");
        LED(0, 192, 255, BRIGHTNESS);   // LED 換顏色 → 表示「下載完成」
        PngDecodeLittleFS("/temp.png"); // 從 LittleFS 中讀取並解碼一張 PNG 圖片
        SaveArray("/1.bin");
        LED(0, 64, 255, BRIGHTNESS); // LED 換顏色 → 表示「讀取、解碼、儲存完成」
        
        // 自動顯示新下載的圖片
        GetArray("/1.bin");
        EPD_4IN0E_Display(epd_bitmap_canvas);
        
        Serial.println("========== 熱更新完成！ ==========");
      }
    }
  }

  // ------------------ 按鈕2處理 ------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn2Value != lastBtn2State)
  {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn2DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn2DebounceTime) > debounceDelay)
  {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn2Value != nowBtn2State)
    {
      nowBtn2State = Btn2Value;
      // 如果按鈕是 HIGH（被按下去）
      if (nowBtn2State == LOW)
      {
        // TODO：這裡可以加上要做的事情（例如切換 LED 狀態）
        LED(1, 92, 255, BRIGHTNESS);          // LED 換顏色 → 表示「PNG 解碼開始」
        GetArray("/2.bin");                   // 讀取圖片2 Array
        LED(1, 192, 255, BRIGHTNESS);         // LED 換顏色 → 表示「PNG 解碼完成」
        EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
        LED(1, 64, 255, BRIGHTNESS);          // LED 顯示另一個顏色 → 表示「顯示完成」
      }
    }
  }

  // ------------------ 按鈕3處理 ------------------
  // 如果「這次讀到的狀態」和「上一次不同」
  if (Btn3Value != lastBtn3State)
  {
    // 更新上次改變時間 → 開始計算防彈跳計時
    lastBtn3DebounceTime = millis();
  }

  // 如果「目前時間 - 上次改變時間」大於防彈跳延遲
  if ((millis() - lastBtn3DebounceTime) > debounceDelay)
  {
    // 表示狀態已經穩定，不是抖動
    // 檢查是否和上一次狀態不同
    if (Btn3Value != nowBtn3State)
    {
      nowBtn3State = Btn3Value;
      // 如果按鈕是 HIGH（被按下去）
      if (nowBtn3State == LOW)
      {
        // TODO：這裡可以加上要做的事情（例如切換 LED 狀態）
        LED(2, 92, 255, BRIGHTNESS);          // LED 換顏色 → 表示「PNG 解碼開始」
        GetArray("/3.bin");                   // 讀取圖片3 Array
        LED(2, 192, 255, BRIGHTNESS);         // LED 換顏色 → 表示「PNG 解碼完成」
        EPD_4IN0E_Display(epd_bitmap_canvas); // 把轉換好的圖像資料送到電子紙顯示
        LED(2, 64, 255, BRIGHTNESS);          // LED 顯示另一個顏色 → 表示「顯示完成」
      }
    }
  }

  // ------------------ 更新狀態 ------------------
  // 把現在的按鈕狀態存起來，下一次 loop() 執行時會用來比對
  lastBtn1State = Btn1Value;
  lastBtn2State = Btn2Value;
  lastBtn3State = Btn3Value;
}
