import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';

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

/// Service for communicating with Arduino E-Paper device via REST API.
///
/// Features:
/// - Automatic fallback from mDNS to IP address
/// - Direct image upload to Arduino (no cloud storage needed)
///
/// API Endpoints:
/// - GET /api/show?slot={1,2,3} - Display image from local storage
/// - GET /api/update?slot={1,2,3} - Download from cloud and display
/// - POST /api/upload?slot={1,2,3} - Upload image directly to Arduino
class ArduinoService {
  late Dio _dio;
  String _currentBaseUrl = AppConfig.arduinoMdnsUrl;
  bool _useFallback = false;

  ArduinoService() {
    _initDio(_currentBaseUrl);
  }

  void _initDio(String baseUrl) {
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

  /// Check if using fallback IP
  bool get isUsingFallback => _useFallback;

  /// Try to connect, with automatic fallback to IP if mDNS fails
  Future<bool> checkConnection() async {
    if (AppConfig.mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }

    // Try mDNS first
    if (!_useFallback) {
      _initDio(AppConfig.arduinoMdnsUrl);
      try {
        final response = await _dio.get('/');
        if (response.statusCode == 200) {
          _currentBaseUrl = AppConfig.arduinoMdnsUrl;
          return true;
        }
      } catch (e) {
        print('mDNS connection failed: $e');
      }
    }

    // Try fallback IP
    _initDio(AppConfig.arduinoIpUrl);
    try {
      final response = await _dio.get('/');
      if (response.statusCode == 200) {
        _currentBaseUrl = AppConfig.arduinoIpUrl;
        _useFallback = true;
        print('Using fallback IP: ${AppConfig.arduinoIpUrl}');
        return true;
      }
    } catch (e) {
      print('IP connection also failed: $e');
    }

    return false;
  }

  /// Force switch to fallback IP
  void switchToFallback() {
    _currentBaseUrl = AppConfig.arduinoIpUrl;
    _useFallback = true;
    _initDio(_currentBaseUrl);
  }

  /// Force switch to mDNS
  void switchToMdns() {
    _currentBaseUrl = AppConfig.arduinoMdnsUrl;
    _useFallback = false;
    _initDio(_currentBaseUrl);
  }

  /// Show image from local storage (slot 1, 2, or 3)
  ///
  /// Calls: GET /api/show?slot={slot}
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
  ///
  /// Calls: GET /api/update?slot={slot}
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
  ///
  /// Calls: POST /api/upload?slot={slot}
  /// This uploads the processed JPEG image directly to the Arduino,
  /// which saves it to local storage and displays it.
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
          // Longer timeout for upload
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
}
