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
  static const bool mockMode = true;

  // ===========================================
  // Arduino Device Configuration
  // ===========================================

  /// Arduino device base URL (mDNS)
  static const String arduinoBaseUrl = 'http://epaper.local';

  /// Alternative: Direct IP address (uncomment and modify if mDNS doesn't work)
  // static const String arduinoBaseUrl = 'http://192.168.1.100';

  /// API endpoints
  static const String apiShow = '/api/show';
  static const String apiUpdate = '/api/update';

  // ===========================================
  // Cloudflare R2 Configuration
  // ===========================================

  /// R2 public base URL for downloading images
  static const String r2PublicUrl =
      'https://REMOVED_R2_PUBLIC_ID.r2.dev';

  /// R2 upload endpoint (for real mode - requires backend or direct R2 API)
  /// Leave empty if using a backend server for uploads
  static const String r2UploadEndpoint = '';

  /// Slot filenames on R2 (must match Arduino's SLOT*_FILENAME)
  static const List<String> slotFilenames = [
    'test.png', // Slot 1
    'cat.png', // Slot 2
    'dog.png', // Slot 3
  ];

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
