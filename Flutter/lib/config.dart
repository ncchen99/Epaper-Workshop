/// Application configuration for LEGO E-Paper Controller
///
/// MQTT-based multi-device architecture.
library;

class AppConfig {
  // ===========================================
  // Mode Configuration
  // ===========================================

  /// When true, uses mock services instead of real API calls.
  static const bool mockMode = false;

  // ===========================================
  // MQTT Broker Configuration
  // ===========================================

  /// MQTT Broker 主機位址
  /// 第一階段：Desktop 區網 IP（執行 Mosquitto 的電腦）
  /// 第二階段：改為雲端 Broker 位址
  static const String mqttBrokerHost = '192.168.1.100';

  /// MQTT Broker 連接埠
  static const int mqttBrokerPort = 1883;

  // ===========================================
  // Cloudflare R2 Configuration
  // ===========================================

  /// R2 公開存取 URL（ESP32 下載圖片用）
  static const String r2PublicUrl =
      'https://REMOVED_R2_PUBLIC_ID.r2.dev';

  // ===========================================
  // Image Processing Configuration
  // ===========================================

  /// Target image width for E-Paper display
  static const int targetWidth = 400;

  /// Target image height for E-Paper display
  static const int targetHeight = 600;

  /// JPEG quality (0-100, lower = smaller file)
  static const int jpegQuality = 85;

  // ===========================================
  // App Settings
  // ===========================================

  /// Maximum number of log entries to display
  static const int maxLogEntries = 5;

  /// MQTT connection timeout in seconds
  static const int mqttConnectTimeout = 10;
}
