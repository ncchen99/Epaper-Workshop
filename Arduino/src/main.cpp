// ==============================================================
// E-Paper Workshop — ESP32-S3 MQTT Firmware
// ==============================================================
// 本 firmware 使用 MQTT 協定接收來自手機 App 的圖片更新指令。
// ESP32 開機後：
// 1. 連線 Wi-Fi
// 2. 讀取自身 MAC Address 並顯示於 E-Paper（供 App 綁定）
// 3. 連線 MQTT Broker，訂閱 devices/{MAC}/cmd
// 4. 收到指令後下載圖片、解碼、顯示
// 5. 回報狀態至 devices/{MAC}/state
// ==============================================================

// ======== 系統與外部函式庫 ========
#include <Adafruit_NeoPixel.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <JPEGDEC.h>
#include <LittleFS.h>
#include <PubSubClient.h>
#include <qrcode.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <pngle.h>

// ======== 專案函式庫 ========
#include "DEV_Config.h"
#include "EPD_4in0e.h"
#include "dither.h"

// ======== 巨集定義 ========
#define EPD_WIDTH EPD_4IN0E_WIDTH
#define EPD_HEIGHT EPD_4IN0E_HEIGHT
#define LED_PIN A0
#define LED_COUNT 3
#define BTN_PIN D9 // 數位按鈕（3-pin: VCC, GND, OUT）

// ======== Wi-Fi 設定 ========
const char *ssid = "fatfat";
const char *password = "88888888";

// ======== MQTT 設定 ========
// 使用 mDNS host 連線 Desktop Mosquitto（IP 變動也可自動追蹤）
const char *MQTT_BROKER_HOSTNAME = "epaper-broker.local";
const int MQTT_PORT = 1883;

// ======== 全域變數 ========
// NeoPixel LED
uint8_t BRIGHTNESS = 5;
Adafruit_NeoPixel strip(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);

// EPD 畫布
uint8_t epd_bitmap_canvas[EPD_WIDTH * EPD_HEIGHT / 2];
uint8_t *png_rgb_canvas =
    (uint8_t *)ps_malloc(EPD_4IN0E_WIDTH * EPD_4IN0E_HEIGHT * 3);

// MQTT
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);
String deviceMac = "";    // e.g., "AABBCC112233"
String cmdTopic = "";     // e.g., "devices/AABBCC112233/cmd"
String stateTopic = "";   // e.g., "devices/AABBCC112233/state"
String mqttClientId = ""; // MQTT client ID
IPAddress mqttBrokerIp;   // 解析後的 Broker IP
bool mqttBrokerResolved = false;

// 處理狀態
volatile bool isProcessing = false;
volatile bool mqttUpdateRequested = false;
String mqttImageUrl = "";
int mqttSlot = 1;

// 按鈕防彈跳
bool lastBtnState = LOW;
bool nowBtnState = LOW;
unsigned long lastBtnDebounceTime = 0;
unsigned long debounceDelay = 50;

// 上一次顯示的 slot（供按鈕再次顯示使用）
int lastDisplayedSlot = 1;
bool hasDecodedImageInRam = false;

// ======== 函式前向宣告 ========
void LED(uint16_t N, uint16_t H, uint8_t S, uint8_t B);
void mqttCallback(char *topic, byte *payload, unsigned int length);
bool resolveMqttBroker();
void mqttReconnect();
void publishState(const char *status, const char *message = nullptr);
void download_PNG_Url(String _url, String _target);
void PngDecodeLittleFS(const String &path);
void JpegDecodeLittleFS(const String &path);
bool showImage(int slot);
void updateImageFromUrl(const String &url, int slot);
String getMacAddress();
void displayMacOnEPaper();
bool displayMacQrOnEPaper();
void setEpdPixel(uint32_t x, uint32_t y, uint8_t colorCode);

// ======================== LED 控制 ========================
void LED(uint16_t N, uint16_t H, uint8_t S, uint8_t B) {
  strip.setPixelColor(N, strip.ColorHSV(H * 256, S, B));
  strip.show();
}

// ======================== MAC Address ========================
String getMacAddress() {
  String mac = WiFi.macAddress(); // e.g., "AA:BB:CC:11:22:33"
  mac.replace(":", "");           // → "AABBCC112233"
  return mac;
}

// ======================== MQTT 狀態回報 ========================
void publishState(const char *status, const char *message) {
  if (!mqttClient.connected())
    return;

  JsonDocument doc;
  doc["mac"] = deviceMac;
  doc["status"] = status;
  if (message) {
    doc["message"] = message;
  }

  char buffer[256];
  serializeJson(doc, buffer);
  mqttClient.publish(stateTopic.c_str(), buffer);
  Serial.printf("MQTT State → %s: %s\n", stateTopic.c_str(), buffer);
}

// ======================== MQTT Callback ========================
// 收到 devices/{MAC}/cmd 的訊息時呼叫
void mqttCallback(char *topic, byte *payload, unsigned int length) {
  Serial.printf("MQTT 收到訊息 [%s] (%u bytes)\n", topic, length);

  // 如果正在處理中，拒絕新的請求
  if (isProcessing) {
    Serial.println("系統忙碌中，忽略此訊息");
    publishState("busy", "Device is processing another request");
    return;
  }

  // 解析 JSON
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, payload, length);
  if (error) {
    Serial.printf("JSON 解析失敗: %s\n", error.c_str());
    publishState("error", "Invalid JSON format");
    return;
  }

  const char *action = doc["action"] | "";
  Serial.printf("Action: %s\n", action);

  if (strcmp(action, "update") == 0) {
    // 圖片更新指令
    const char *url = doc["url"] | "";
    int slot = doc["slot"] | 1;

    if (strlen(url) == 0) {
      Serial.println("錯誤：缺少 url 參數");
      publishState("error", "Missing image URL");
      return;
    }

    // 設定 flag，讓 loop() 處理（避免在 callback 中執行耗時操作）
    mqttImageUrl = String(url);
    mqttSlot = slot;
    mqttUpdateRequested = true;
    Serial.printf("排程更新：Slot %d, URL: %s\n", slot, url);
    publishState("queued", "Update request received");

  } else if (strcmp(action, "show") == 0) {
    // 直接重繪 RAM 中最近一次解碼完成的圖片
    int slot = doc["slot"] | 1;
    Serial.printf("顯示 Slot %d\n", slot);
    showImage(slot);

  } else if (strcmp(action, "clear") == 0) {
    // 清除畫面
    Serial.println("清除 E-Paper 畫面");
    EPD_4IN0E_Clear(EPD_4IN0E_WHITE);
    publishState("success", "Display cleared");

  } else {
    Serial.printf("未知的 action: %s\n", action);
    publishState("error", "Unknown action");
  }
}

// ======================== MQTT 連線管理 ========================
bool resolveMqttBroker() {
  IPAddress resolvedIp;

  // 先走系統 DNS（在支援 mDNS 的環境可直接解析 *.local）
  if (WiFi.hostByName(MQTT_BROKER_HOSTNAME, resolvedIp)) {
    mqttBrokerIp = resolvedIp;
    mqttBrokerResolved = true;
    Serial.printf("Broker 解析成功: %s -> %s\n", MQTT_BROKER_HOSTNAME,
                  mqttBrokerIp.toString().c_str());
    return true;
  }

  // 再嘗試透過 ESPmDNS 主動查詢
  String hostNoLocal = MQTT_BROKER_HOSTNAME;
  hostNoLocal.replace(".local", "");
  int answers = MDNS.queryHost(hostNoLocal.c_str(), 2000);
  if (answers > 0) {
    mqttBrokerIp = MDNS.IP(0);
    mqttBrokerResolved = true;
    Serial.printf("Broker mDNS 查詢成功: %s -> %s\n", MQTT_BROKER_HOSTNAME,
                  mqttBrokerIp.toString().c_str());
    return true;
  }

  mqttBrokerResolved = false;
  Serial.printf("Broker 解析失敗: %s\n", MQTT_BROKER_HOSTNAME);
  return false;
}

void mqttReconnect() {
  while (!mqttClient.connected()) {
    if (!resolveMqttBroker()) {
      Serial.println("5 秒後重試解析 Broker...");

      LED(0, 0, 255, BRIGHTNESS);
      LED(1, 0, 255, BRIGHTNESS);
      LED(2, 0, 255, BRIGHTNESS);

      delay(5000);
      continue;
    }

    mqttClient.setServer(mqttBrokerIp, MQTT_PORT);

    Serial.printf("連線 MQTT Broker (%s -> %s:%d)...\n", MQTT_BROKER_HOSTNAME,
                  mqttBrokerIp.toString().c_str(), MQTT_PORT);

    // LED 閃爍表示正在連線
    LED(0, 48, 255, BRIGHTNESS);
    LED(1, 48, 255, BRIGHTNESS);
    LED(2, 48, 255, BRIGHTNESS);

    if (mqttClient.connect(mqttClientId.c_str())) {
      Serial.println("MQTT 連線成功！");
      Serial.printf("Client ID: %s\n", mqttClientId.c_str());

      // 訂閱自己的指令 Topic
      mqttClient.subscribe(cmdTopic.c_str());
      Serial.printf("已訂閱: %s\n", cmdTopic.c_str());

      // 回報上線狀態
      publishState("online", "Device connected");

      // LED 顯示已連線
      LED(0, 64, 255, BRIGHTNESS);
      LED(1, 64, 255, BRIGHTNESS);
      LED(2, 64, 255, BRIGHTNESS);
    } else {
      Serial.printf("MQTT 連線失敗，rc=%d，5 秒後重試...\n",
                    mqttClient.state());

      // LED 顯示連線失敗
      LED(0, 0, 255, BRIGHTNESS);
      LED(1, 0, 255, BRIGHTNESS);
      LED(2, 0, 255, BRIGHTNESS);

      delay(5000);
    }
  }
}

// ======================== PNG 解碼相關 ========================
static uint32_t totalPixelCount = 0;
static uint32_t packedPixelCount = 0;
static uint8_t pixelPairIndex = 0;
static uint8_t firstPixelColorCode = 0;
static uint8_t secondPixelColorCode = 0;
static uint32_t millisPNG = 0;
static volatile bool failed = false;
static uint32_t imgW = 0, imgH = 0;

void setEpdPixel(uint32_t x, uint32_t y, uint8_t colorCode) {
  if (x >= EPD_WIDTH || y >= EPD_HEIGHT)
    return;

  const size_t pixelIndex = (size_t)y * EPD_WIDTH + x;
  const size_t byteIndex = pixelIndex / 2;

  if ((pixelIndex & 0x01) == 0) {
    epd_bitmap_canvas[byteIndex] =
        (epd_bitmap_canvas[byteIndex] & 0x0F) | ((colorCode & 0x0F) << 4);
  } else {
    epd_bitmap_canvas[byteIndex] =
        (epd_bitmap_canvas[byteIndex] & 0xF0) | (colorCode & 0x0F);
  }
}

static inline void resetDecodeState() {
  failed = false;
  totalPixelCount = 0;
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;
  millisPNG = millis();
  if (png_rgb_canvas && imgW && imgH) {
    memset(png_rgb_canvas, 0, imgW * imgH * 3);
  }
  if (epd_bitmap_canvas) {
    memset(epd_bitmap_canvas, 0, EPD_WIDTH * EPD_HEIGHT / 2);
  }
}

void initCallback(pngle_t *pngle, uint32_t w, uint32_t h) {
  imgW = w;
  imgH = h;

  if (imgW != EPD_WIDTH || imgH != EPD_HEIGHT) {
    Serial.println("========== 錯誤：PNG 尺寸不符！ ==========");
    Serial.printf("PNG 尺寸: %ux%u\n", imgW, imgH);
    Serial.printf("EPD 尺寸: %ux%u\n", EPD_WIDTH, EPD_HEIGHT);
    failed = true;
    return;
  }

  size_t need = (size_t)imgW * imgH * 3;
  if (png_rgb_canvas) {
    free(png_rgb_canvas);
    png_rgb_canvas = nullptr;
  }
  png_rgb_canvas = (uint8_t *)ps_malloc(need);
  if (!png_rgb_canvas) {
    Serial.println("malloc RGB canvas fail");
    failed = true;
    return;
  }
  memset(png_rgb_canvas, 0, need);

  Serial.println("開始處理 PNG 圖片");
  millisPNG = millis();
  totalPixelCount = 0;
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;

  Serial.printf("PNG 圖片: %u x %u\n", w, h);
  resetDecodeState();
}

void drawCallback(pngle_t *pngle, uint32_t x, uint32_t y, uint32_t w,
                  uint32_t h, const uint8_t rgba[4]) {
  if (!png_rgb_canvas)
    return;
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

// 將 RGB 像素轉換為 EPD 色碼並打包
static void packRgbToEpd() {
  packedPixelCount = 0;
  pixelPairIndex = 0;
  firstPixelColorCode = 0;
  secondPixelColorCode = 0;

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

    if (i % 50000 == 0)
      delay(1);
  }
}

void doneCallback(pngle_t *pngle) {
  if (failed || !png_rgb_canvas)
    return;

  Serial.print("dithering...");
  dither(png_rgb_canvas, EPD_WIDTH, EPD_HEIGHT);
  packRgbToEpd();

  Serial.printf("完成像素解碼：%u 個\n", totalPixelCount);
  uint32_t el = millis() - millisPNG;
  Serial.printf("共耗時：%u.%03u秒\n", el / 1000, el % 1000);
}

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

// ======================== JPEG 解碼相關 ========================
JPEGDEC jpeg;
File jpegFile;

void *jpegOpen(const char *filename, int32_t *size) {
  jpegFile = LittleFS.open(filename, "r");
  if (!jpegFile)
    return nullptr;
  *size = jpegFile.size();
  return &jpegFile;
}

void jpegClose(void *handle) {
  if (jpegFile)
    jpegFile.close();
}

int32_t jpegRead(JPEGFILE *handle, uint8_t *buffer, int32_t length) {
  if (!jpegFile)
    return 0;
  return jpegFile.read(buffer, length);
}

int32_t jpegSeek(JPEGFILE *handle, int32_t position) {
  if (!jpegFile)
    return 0;
  return jpegFile.seek(position);
}

int jpegDrawCallback(JPEGDRAW *pDraw) {
  for (int y = 0; y < pDraw->iHeight; y++) {
    for (int x = 0; x < pDraw->iWidth; x++) {
      int destX = pDraw->x + x;
      int destY = pDraw->y + y;

      if (destX < EPD_WIDTH && destY < EPD_HEIGHT) {
        uint16_t pixel = pDraw->pPixels[y * pDraw->iWidth + x];
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
  return 1;
}

void JpegDecodeLittleFS(const String &path) {
  Serial.println("DecodeJPEG...");

  if (!png_rgb_canvas) {
    png_rgb_canvas = (uint8_t *)ps_malloc(EPD_WIDTH * EPD_HEIGHT * 3);
    if (!png_rgb_canvas) {
      Serial.println("無法分配 RGB 畫布記憶體！");
      return;
    }
  }
  memset(png_rgb_canvas, 255, EPD_WIDTH * EPD_HEIGHT * 3);

  if (jpeg.open(path.c_str(), jpegOpen, jpegClose, jpegRead, jpegSeek,
                jpegDrawCallback)) {
    int imgWidth = jpeg.getWidth();
    int imgHeight = jpeg.getHeight();
    Serial.printf("JPEG 圖片: %d x %d\n", imgWidth, imgHeight);

    if (imgWidth > EPD_WIDTH * 2 || imgHeight > EPD_HEIGHT * 2) {
      Serial.println("警告: 圖片太大");
    }

    unsigned long startTime = millis();
    int options = 0;
    if (imgWidth >= EPD_WIDTH * 2 || imgHeight >= EPD_HEIGHT * 2) {
      options = JPEG_SCALE_HALF;
      Serial.println("使用 1/2 縮放解碼...");
    }

    Serial.println("開始解碼...");
    if (jpeg.decode(0, 0, options)) {
      Serial.printf("JPEG 解碼成功！耗時 %lu ms\n", millis() - startTime);

      Serial.println("執行抖動處理...");
      dither(png_rgb_canvas, EPD_WIDTH, EPD_HEIGHT);
      packRgbToEpd();
      Serial.println("JPEG 處理完成！");
    } else {
      Serial.printf("JPEG 解碼失敗！錯誤代碼: %d\n", jpeg.getLastError());
    }
    jpeg.close();
  } else {
    Serial.println("無法開啟 JPEG 檔案！");
  }
}

// ======================== 圖片下載 ========================
void download_PNG_Url(String _url, String _target) {
  Serial.println("開始下載圖片...");
  Serial.println("URL: " + _url);

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("錯誤: WiFi 未連線！");
    return;
  }

  const int maxRetries = 3;
  int retryCount = 0;
  bool downloadSuccess = false;
  bool writeSuccess = false;

  while (retryCount < maxRetries) {
    HTTPClient http;
    http.begin(_url);
    http.setTimeout(30000);

    Serial.println("發送 GET 請求...");
    int httpCode = http.GET();
    Serial.printf("HTTP 回應碼: %d\n", httpCode);

    if (httpCode == HTTP_CODE_OK) {
      Serial.println("下載成功");
      downloadSuccess = true;

      if (LittleFS.exists(_target)) {
        LittleFS.remove(_target);
      }

      int writeRetryCount = 0;
      while (writeRetryCount < maxRetries) {
        File file = LittleFS.open(_target, FILE_WRITE);
        if (!file) {
          writeRetryCount++;
          delay(100);
          continue;
        }

        int writtenBytes = http.writeToStream(&file);
        if (writtenBytes > 0) {
          file.close();

          File verifyFile = LittleFS.open(_target, FILE_READ);
          if (verifyFile) {
            if (verifyFile.size() > 0) {
              writeSuccess = true;
            }
            verifyFile.close();
          }
          break;
        } else {
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
    }

    http.end();
    retryCount++;
    delay(1000);
  }

  if (!downloadSuccess) {
    Serial.println("下載失敗！");
  } else if (!writeSuccess) {
    Serial.println("檔案寫入失敗！");
  } else {
    Serial.println("圖片下載並儲存成功！");
  }

  delay(100);
}

// ======================== 顯示圖片 ========================
bool showImage(int slot) {
  Serial.printf("顯示圖片請求: Slot %d\n", slot);

  if (!hasDecodedImageInRam) {
    Serial.println("錯誤: RAM 中沒有可顯示的已解碼圖片");
    publishState("error", "No decoded image in memory yet");
    return false;
  }

  isProcessing = true;
  publishState("displaying", "Rendering decoded image from RAM");

  LED(0, 92, 255, BRIGHTNESS);
  LED(0, 192, 255, BRIGHTNESS);

  Serial.println("正在刷新電子紙...");
  unsigned long startTime = millis();
  EPD_4IN0E_Display(epd_bitmap_canvas);
  Serial.printf("刷新完成！耗時 %lu ms\n", millis() - startTime);

  LED(0, 64, 255, BRIGHTNESS);
  lastDisplayedSlot = slot;
  publishState("success", "Image displayed");

  // ESP.restart() — 保留但註解，待觀察是否需要
  // Serial.println("0.5 秒後重啟 ESP32...");
  // delay(500);
  // ESP.restart();

  isProcessing = false;
  return true;
}

// ======================== 從 URL 更新圖片 ========================
void updateImageFromUrl(const String &url, int slot) {
  Serial.printf("更新圖片 Slot %d\n", slot);
  Serial.println("URL: " + url);

  isProcessing = true;
  publishState("downloading", "Downloading image...");

  LED(0, 160, 255, BRIGHTNESS);

  // 判斷副檔名
  String lowerUrl = url;
  lowerUrl.toLowerCase();
  bool isJpeg = lowerUrl.endsWith(".jpg") || lowerUrl.endsWith(".jpeg");
  String tempFile = isJpeg ? "/temp.jpg" : "/temp.png";

  // 下載圖片
  download_PNG_Url(url, tempFile);
  LED(0, 192, 255, BRIGHTNESS);

  // 解碼
  publishState("decoding", "Decoding image...");
  if (isJpeg) {
    Serial.println("使用 JPEG 解碼器");
    JpegDecodeLittleFS(tempFile);
  } else {
    Serial.println("使用 PNG 解碼器");
    PngDecodeLittleFS(tempFile);
  }

  Serial.println("解碼完成");
  LED(0, 64, 255, BRIGHTNESS);

  // 刷新 E-Paper
  publishState("displaying", "Refreshing display...");
  Serial.println("正在刷新電子紙...");
  unsigned long startTime = millis();
  EPD_4IN0E_Display(epd_bitmap_canvas);
  Serial.printf("刷新完成！耗時 %lu ms\n", millis() - startTime);

  LED(0, 64, 255, BRIGHTNESS);
  lastDisplayedSlot = slot;
  hasDecodedImageInRam = true;

  // 清理暫存檔
  LittleFS.remove(tempFile);

  publishState("success", "Image updated and displayed");
  Serial.println("更新完成！");

  // ESP.restart() — 保留但註解，待觀察是否需要
  // Serial.println("2 秒後重啟 ESP32...");
  // delay(2000);
  // ESP.restart();

  isProcessing = false;
}

// ======================== 開機顯示 MAC ========================
void displayMacOnEPaper() {
  // 在 E-Paper 上用簡單文字顯示 MAC Address
  // 使用黑底白字，讓使用者可以在 App 中輸入 MAC 進行綁定

  // 清空畫布為白色
  memset(epd_bitmap_canvas, 0x11, EPD_WIDTH * EPD_HEIGHT / 2);
  // 0x11 = 兩個像素都是 WHITE (color code 1)

  // 注意：由於 EPD 沒有內建字型渲染，這裡改為在 Serial 輸出 MAC
  // 使用者可以從 Serial Monitor 讀取 MAC Address
  // 未來可加入 QR Code 或字型渲染來在螢幕上顯示

  Serial.println("===========================================");
  Serial.println("  裝置 MAC Address: " + deviceMac);
  Serial.println("  MQTT cmd Topic:   " + cmdTopic);
  Serial.println("  MQTT state Topic: " + stateTopic);
  Serial.println("===========================================");
  Serial.println("按下 D9 按鈕可在 E-Paper 顯示 MAC QR Code，供 App 掃描綁定");
}

bool displayMacQrOnEPaper() {
  if (deviceMac.length() != 12) {
    Serial.println("無法顯示 QR：MAC 長度錯誤");
    publishState("error", "Invalid MAC length for QR");
    return false;
  }

  // 內容保持純 MAC（12 碼）讓 App 可直接正規化使用
  const String qrPayload = deviceMac;
  uint8_t qrVersion = 6;
  const uint8_t ecLevel = 0;
  const uint16_t qrDataSize = qrcode_getBufferSize(qrVersion);
  uint8_t *qrcodeData = (uint8_t *)malloc(qrDataSize);
  if (!qrcodeData) {
    Serial.println("無法顯示 QR：記憶體不足");
    publishState("error", "Out of memory for QR buffer");
    return false;
  }

  QRCode qrcode;
  qrcode_initText(&qrcode, qrcodeData, qrVersion, ecLevel, qrPayload.c_str());

  const int quietZoneModules = 4;
  const int qrModulesWithQuiet = qrcode.size + quietZoneModules * 2;
  const int moduleScale = min((int)EPD_WIDTH, (int)EPD_HEIGHT) / qrModulesWithQuiet;
  if (moduleScale <= 0) {
    Serial.println("無法顯示 QR：模組縮放比例無效");
    publishState("error", "QR scale error");
    free(qrcodeData);
    return false;
  }

  const int qrPixelSize = qrModulesWithQuiet * moduleScale;
  const int startX = ((int)EPD_WIDTH - qrPixelSize) / 2;
  const int startY = ((int)EPD_HEIGHT - qrPixelSize) / 2;

  memset(epd_bitmap_canvas, 0x11, EPD_WIDTH * EPD_HEIGHT / 2);

  for (int my = 0; my < qrcode.size; ++my) {
    for (int mx = 0; mx < qrcode.size; ++mx) {
      const bool isBlack = qrcode_getModule(&qrcode, mx, my);
      const uint8_t color = isBlack ? EPD_4IN0E_BLACK : EPD_4IN0E_WHITE;

      const int drawX = startX + (mx + quietZoneModules) * moduleScale;
      const int drawY = startY + (my + quietZoneModules) * moduleScale;

      for (int dy = 0; dy < moduleScale; ++dy) {
        for (int dx = 0; dx < moduleScale; ++dx) {
          setEpdPixel(drawX + dx, drawY + dy, color);
        }
      }
    }
  }

  isProcessing = true;
  publishState("displaying", "Showing device QR code");

  LED(0, 92, 255, BRIGHTNESS);
  LED(1, 92, 255, BRIGHTNESS);
  LED(2, 92, 255, BRIGHTNESS);

  unsigned long startTime = millis();
  EPD_4IN0E_Display(epd_bitmap_canvas);
  Serial.printf("MAC QR 顯示完成，耗時 %lu ms\n", millis() - startTime);
  Serial.println("掃描內容 (MAC): " + qrPayload);

  LED(0, 64, 255, BRIGHTNESS);
  LED(1, 64, 255, BRIGHTNESS);
  LED(2, 64, 255, BRIGHTNESS);

  publishState("success", "Device MAC QR displayed");
  isProcessing = false;
  free(qrcodeData);
  return true;
}

// ======================== Setup ========================
void setup() {
  Serial.begin(9600);

  // 初始化 NeoPixel LED
  strip.begin();
  LED(0, 0, 0, 0);
  LED(1, 0, 0, 0);
  LED(2, 0, 0, 0);
  delay(1000);

  // ---- Wi-Fi 連線 ----
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    LED(0, 32, 255, BRIGHTNESS);
    LED(1, 32, 255, BRIGHTNESS);
    LED(2, 32, 255, BRIGHTNESS);
    delay(1000);
    Serial.println("Connecting to WiFi...");
  }
  Serial.println("Connected to WiFi");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // ---- 取得 MAC Address ----
  deviceMac = getMacAddress();
  cmdTopic = "devices/" + deviceMac + "/cmd";
  stateTopic = "devices/" + deviceMac + "/state";
  mqttClientId = "epaper_" + deviceMac;

  Serial.println("MAC Address: " + deviceMac);
  Serial.println("CMD Topic:   " + cmdTopic);
  Serial.println("State Topic: " + stateTopic);

  // ---- 初始化 mDNS（供主動查詢 .local 主機）----
  String mdnsHost = "epaper-" + deviceMac.substring(deviceMac.length() - 6);
  if (MDNS.begin(mdnsHost.c_str())) {
    Serial.printf("mDNS responder 已啟用: %s.local\n", mdnsHost.c_str());
  } else {
    Serial.println("mDNS responder 啟用失敗，仍會嘗試一般 DNS 解析");
  }

  // ---- MQTT 設定 ----
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(1024); // 預設 256 太小，需加大以容納 JSON

  // ---- LittleFS 初始化 ----
  LED(0, 16, 255, BRIGHTNESS);
  LED(1, 16, 255, BRIGHTNESS);
  LED(2, 16, 255, BRIGHTNESS);
  Serial.println("Testing LittleFS...");
  while (!LittleFS.begin(true)) {
    LED(0, 0, 255, BRIGHTNESS);
    delay(200);
    LED(0, 0, 255, 0);
    delay(200);
    Serial.println("LittleFS Fail...");
  }
  Serial.println("LittleFS Done!");

  // 格式化 LittleFS
  Serial.println("Formatting LittleFS...");
  if (LittleFS.format()) {
    Serial.println("LittleFS formatted successfully!");
  } else {
    Serial.println("LittleFS format failed!");
  }

  // ---- 分配 RGB 畫布 ----
  png_rgb_canvas = (uint8_t *)ps_malloc(EPD_4IN0E_WIDTH * EPD_4IN0E_HEIGHT * 3);
  memset(epd_bitmap_canvas, 0x00, EPD_WIDTH * EPD_HEIGHT / 2);

  // ---- 按鈕設定 ----
  // D9 數位按鈕（3-pin: VCC, GND, OUT）
  // 按下時 OUT 輸出 HIGH
  pinMode(BTN_PIN, INPUT);

  // ---- 初始化 E-Paper ----
  LED(0, 32, 255, BRIGHTNESS);
  LED(1, 32, 255, BRIGHTNESS);
  LED(2, 32, 255, BRIGHTNESS);
  DEV_Module_Init();
  EPD_4IN0E_Init();
  LED(0, 128, 255, BRIGHTNESS);
  LED(1, 128, 255, BRIGHTNESS);
  LED(2, 128, 255, BRIGHTNESS);

  // ---- 顯示 MAC Address ----
  displayMacOnEPaper();

  // ---- 連線 MQTT ----
  mqttReconnect();

  Serial.println("Setup 完成！");
  Serial.println("等待 MQTT 指令...");
  Serial.printf("  - Broker: %s:%d\n", MQTT_BROKER_HOSTNAME, MQTT_PORT);
  if (mqttBrokerResolved) {
    Serial.printf("  - Resolved IP: %s\n", mqttBrokerIp.toString().c_str());
  }
  Serial.printf("  - 訂閱:   %s\n", cmdTopic.c_str());
  Serial.printf("  - 回報:   %s\n", stateTopic.c_str());
}

// ======================== Loop ========================
void loop() {
  yield();

  // ---- MQTT 連線維護 ----
  if (!mqttClient.connected()) {
    mqttReconnect();
  }
  mqttClient.loop();

  // ---- 處理 MQTT 更新請求 ----
  if (mqttUpdateRequested && !isProcessing) {
    mqttUpdateRequested = false;
    updateImageFromUrl(mqttImageUrl, mqttSlot);
  }

  // ---- 按鈕處理（D9 單按鈕）----
  bool btnValue = digitalRead(BTN_PIN);

  if (btnValue != lastBtnState) {
    lastBtnDebounceTime = millis();
  }

  if ((millis() - lastBtnDebounceTime) > debounceDelay) {
    if (btnValue != nowBtnState) {
      nowBtnState = btnValue;

      // 按鈕按下（HIGH）時觸發：顯示裝置 MAC 的 QR Code
      if (nowBtnState == HIGH) {
        Serial.println("按鈕按下 → 顯示裝置 MAC QR Code");
        if (!isProcessing) {
          displayMacQrOnEPaper();
        }
      }
    }
  }

  lastBtnState = btnValue;
}
