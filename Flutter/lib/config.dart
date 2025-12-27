/// Application configuration for LEGO E-Paper Controller
///
/// Toggle [mockMode] to switch between mock and real API calls.
library;

class AppConfig {
  // ===========================================
  // Mode Configuration
  // ===========================================

  /// When true, uses mock services instead of real API calls.
  /// Set to false when ready to connect to real Arduino device.
  static const bool mockMode = false;

  // ===========================================
  // Arduino Device Configuration
  // ===========================================

  /// Primary: Arduino device mDNS hostname
  /// Works on iOS and most networks
  static const String arduinoMdnsUrl = 'http://epaper.local';

  /// Fallback: Direct IP address
  /// Use this when mDNS doesn't work (common on Android)
  static const String arduinoIpUrl = 'http://10.85.182.1';

  /// API endpoints
  static const String apiShow = '/api/show';
  static const String apiUpdate = '/api/update';
  static const String apiUpload = '/api/upload'; // Direct upload to Arduino

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

  /// Connection timeout in milliseconds
  static const int connectionTimeout = 10000;

  /// Request timeout in milliseconds
  static const int requestTimeout = 30000;
}
