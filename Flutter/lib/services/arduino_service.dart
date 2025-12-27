import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';
import 'discovery_service.dart';

/// Result of an Arduino API call
class ArduinoResult {
  final bool success;
  final String? message;
  final String? error;

  const ArduinoResult({required this.success, this.message, this.error});

  factory ArduinoResult.ok([String? message]) =>
      ArduinoResult(success: true, message: message ?? 'OK');

  factory ArduinoResult.failure(String error) =>
      ArduinoResult(success: false, error: error);
}

/// Connection method used to connect to the Arduino
enum ConnectionMethod {
  mdnsDiscovery, // Found via mDNS/DNS-SD discovery
  mdnsDirect, // Tried epaper.local directly
  fallbackIp, // Using fallback IP address
  notConnected,
}

/// Service for communicating with Arduino E-Paper device via REST API.
///
/// Features:
/// - Native mDNS discovery (Android NSD + iOS Bonjour)
/// - Automatic fallback to IP address
/// - Direct image upload to Arduino (no cloud storage needed)
///
/// API Endpoints:
/// - GET /api/show?slot={1,2,3} - Display image from local storage
/// - GET /api/update?slot={1,2,3} - Download from cloud and display
/// - POST /api/upload?slot={1,2,3} - Upload image directly to Arduino
class ArduinoService {
  late Dio _dio;
  String _currentBaseUrl = '';
  ConnectionMethod _connectionMethod = ConnectionMethod.notConnected;
  final DiscoveryService _discoveryService = DiscoveryService();

  ArduinoService() {
    _initDio(AppConfig.arduinoIpUrl);
  }

  void _initDio(String baseUrl) {
    _currentBaseUrl = baseUrl;
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: Duration(milliseconds: AppConfig.connectionTimeout),
        receiveTimeout: Duration(milliseconds: AppConfig.requestTimeout),
      ),
    );
  }

  /// Get current connection URL (for display purposes)
  String get currentUrl => _currentBaseUrl;

  /// Get current connection method
  ConnectionMethod get connectionMethod => _connectionMethod;

  /// Get human-readable connection status
  String get connectionStatus {
    switch (_connectionMethod) {
      case ConnectionMethod.mdnsDiscovery:
        return 'Connected via mDNS Discovery';
      case ConnectionMethod.mdnsDirect:
        return 'Connected via epaper.local';
      case ConnectionMethod.fallbackIp:
        return 'Connected via IP (${AppConfig.arduinoIpUrl})';
      case ConnectionMethod.notConnected:
        return 'Not connected';
    }
  }

  /// Check if using fallback IP
  bool get isUsingFallback => _connectionMethod == ConnectionMethod.fallbackIp;

  /// Try to connect using the best available method
  ///
  /// Priority:
  /// 1. Native mDNS discovery (most reliable on Android)
  /// 2. Direct mDNS URL (epaper.local)
  /// 3. Fallback IP address
  Future<bool> checkConnection() async {
    if (AppConfig.mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      _connectionMethod = ConnectionMethod.mdnsDiscovery;
      return true;
    }

    // Method 1: Try native mDNS discovery
    final discoveredUrl = await _discoveryService.discoverDevice(
      timeout: const Duration(seconds: 3),
    );

    if (discoveredUrl != null && discoveredUrl != AppConfig.arduinoIpUrl) {
      _initDio(discoveredUrl);
      if (await _testConnection()) {
        _connectionMethod = ConnectionMethod.mdnsDiscovery;
        return true;
      }
    }

    // Method 2: Try direct mDNS URL
    _initDio(AppConfig.arduinoMdnsUrl);
    if (await _testConnection()) {
      _connectionMethod = ConnectionMethod.mdnsDirect;
      return true;
    }

    // Method 3: Try fallback IP
    _initDio(AppConfig.arduinoIpUrl);
    if (await _testConnection()) {
      _connectionMethod = ConnectionMethod.fallbackIp;
      return true;
    }

    _connectionMethod = ConnectionMethod.notConnected;
    return false;
  }

  /// Test if current connection works
  Future<bool> _testConnection() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Force switch to fallback IP
  void switchToFallback() {
    _initDio(AppConfig.arduinoIpUrl);
    _connectionMethod = ConnectionMethod.fallbackIp;
  }

  /// Force switch to mDNS
  void switchToMdns() {
    _initDio(AppConfig.arduinoMdnsUrl);
    _connectionMethod = ConnectionMethod.mdnsDirect;
  }

  /// Show image from local storage (slot 1, 2, or 3)
  Future<ArduinoResult> showImage(int slot) async {
    if (slot < 1 || slot > 3) {
      return ArduinoResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      await Future.delayed(const Duration(milliseconds: 800));
      return ArduinoResult.ok('Mock: Displaying image from slot $slot');
    }

    try {
      final response = await _dio.get(
        AppConfig.apiShow,
        queryParameters: {'slot': slot},
      );

      if (response.statusCode == 200) {
        return ArduinoResult.ok('Image from slot $slot displayed');
      } else {
        return ArduinoResult.failure('API returned: ${response.data}');
      }
    } on DioException catch (e) {
      return ArduinoResult.failure(_handleDioError(e));
    } catch (e) {
      return ArduinoResult.failure('Unknown error: $e');
    }
  }

  /// Update image from cloud and display (slot 1, 2, or 3)
  Future<ArduinoResult> updateImage(int slot) async {
    if (slot < 1 || slot > 3) {
      return ArduinoResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      await Future.delayed(const Duration(milliseconds: 1500));
      return ArduinoResult.ok('Mock: Updated and displayed slot $slot');
    }

    try {
      final response = await _dio.get(
        AppConfig.apiUpdate,
        queryParameters: {'slot': slot},
      );

      if (response.statusCode == 200) {
        return ArduinoResult.ok('Slot $slot updated from cloud and displayed');
      } else {
        return ArduinoResult.failure('API returned: ${response.data}');
      }
    } on DioException catch (e) {
      return ArduinoResult.failure(_handleDioError(e));
    } catch (e) {
      return ArduinoResult.failure('Unknown error: $e');
    }
  }

  /// Upload image directly to Arduino and display
  Future<ArduinoResult> uploadImage(int slot, File imageFile) async {
    if (slot < 1 || slot > 3) {
      return ArduinoResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      await Future.delayed(const Duration(milliseconds: 2000));
      return ArduinoResult.ok('Mock: Uploaded and displayed slot $slot');
    }

    try {
      // Read file as bytes
      final bytes = await imageFile.readAsBytes();

      // Create form data with the image
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: 'slot_$slot.jpg'),
      });

      final response = await _dio.post(
        AppConfig.apiUpload,
        queryParameters: {'slot': slot},
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      if (response.statusCode == 200) {
        return ArduinoResult.ok('Image uploaded to slot $slot and displayed');
      } else {
        return ArduinoResult.failure('Upload failed: ${response.data}');
      }
    } on DioException catch (e) {
      return ArduinoResult.failure(_handleDioError(e));
    } catch (e) {
      return ArduinoResult.failure('Upload error: $e');
    }
  }

  /// Handle Dio errors and return user-friendly messages
  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Check if device is powered on.';
      case DioExceptionType.sendTimeout:
        return 'Upload timeout. The image may be too large.';
      case DioExceptionType.receiveTimeout:
        return 'Response timeout. E-Paper update may take a while.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to device. Check WiFi connection.';
      default:
        return e.message ?? 'Network error occurred';
    }
  }

  /// Dispose resources
  void dispose() {
    _discoveryService.dispose();
  }
}
