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
/// API Endpoints:
/// - GET /api/show?slot={1,2,3} - Display image from local storage
/// - GET /api/update?slot={1,2,3} - Download from cloud and display
class ArduinoService {
  late final Dio _dio;

  ArduinoService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.arduinoBaseUrl,
        connectTimeout: Duration(milliseconds: AppConfig.connectionTimeout),
        receiveTimeout: Duration(milliseconds: AppConfig.requestTimeout),
      ),
    );
  }

  /// Check if device is reachable
  Future<bool> checkConnection() async {
    if (AppConfig.mockMode) {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }

    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Show image from local storage (slot 1, 2, or 3)
  ///
  /// Calls: GET /api/show?slot={slot}
  Future<ArduinoResult> showImage(int slot) async {
    if (slot < 1 || slot > 3) {
      return ArduinoResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      // Simulate API call
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
  /// This tells the Arduino to:
  /// 1. Download the latest image for this slot from the cloud
  /// 2. Save it to local storage
  /// 3. Display it on the E-Paper
  Future<ArduinoResult> updateImage(int slot) async {
    if (slot < 1 || slot > 3) {
      return ArduinoResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      // Simulate longer delay for update (download + display)
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

  /// Handle Dio errors and return user-friendly messages
  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Check if device is powered on.';
      case DioExceptionType.receiveTimeout:
        return 'Response timeout. E-Paper update may take a while.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to device. Check WiFi connection.';
      default:
        return e.message ?? 'Network error occurred';
    }
  }
}
