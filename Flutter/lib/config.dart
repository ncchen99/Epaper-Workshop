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
  /// 使用 mDNS hostname，避免硬編碼 IP。
  static const String mqttBrokerHost = 'epaper-broker.local';

  /// 備援 Broker 主機（可用 --dart-define 設定）
  /// 範例：--dart-define=MQTT_BROKER_FALLBACK_HOST=192.168.1.100
  static const String mqttBrokerFallbackHost = String.fromEnvironment(
    'MQTT_BROKER_FALLBACK_HOST',
    defaultValue: '',
  );

  /// MQTT Broker 連接埠
  static const int mqttBrokerPort = 1883;

  /// MQTT 連線逾時秒數
  static const int mqttConnectTimeoutSeconds = 10;

  /// mDNS 解析逾時秒數
  static const int mqttMdnsLookupTimeoutSeconds = 3;

  /// 依序嘗試的 Broker 主機清單（主機名 + 可選備援）
  static List<String> mqttBrokerCandidates() {
    final candidates = <String>[mqttBrokerHost];

    // 使用 127.0.0.1 (確定的 IPv4) 避開模擬器上 localhost 可能解析為 IPv6 (::1) 的問題。
    if (!candidates.contains('127.0.0.1')) {
      candidates.add('127.0.0.1');
    }
    if (!candidates.contains('10.0.2.2')) {
      candidates.add('10.0.2.2');
    }

    if (mqttBrokerFallbackHost.isNotEmpty &&
        !candidates.contains(mqttBrokerFallbackHost)) {
      candidates.add(mqttBrokerFallbackHost);
    }
    return candidates;
  }

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
