import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';

/// Result of an upload operation
class UploadResult {
  final bool success;
  final String? imageUrl;
  final String? error;

  const UploadResult({required this.success, this.imageUrl, this.error});

  factory UploadResult.ok(String imageUrl) =>
      UploadResult(success: true, imageUrl: imageUrl);

  factory UploadResult.failure(String error) =>
      UploadResult(success: false, error: error);
}

/// Service for uploading images to Cloudflare R2.
///
/// In mock mode, simulates the upload and returns a fake URL.
/// In real mode, uploads to R2 (requires backend or direct R2 API implementation).
class UploadService {
  late final Dio _dio;

  UploadService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: AppConfig.connectionTimeout),
        receiveTimeout: Duration(milliseconds: AppConfig.requestTimeout),
      ),
    );
  }

  /// Upload an image file for a specific slot.
  ///
  /// [image] - The image file to upload
  /// [slot] - The slot number (1, 2, or 3) determines the filename
  ///
  /// Returns the public URL of the uploaded image.
  Future<UploadResult> uploadImage(File image, int slot) async {
    if (slot < 1 || slot > 3) {
      return UploadResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    final filename = AppConfig.slotFilenames[slot - 1];

    if (AppConfig.mockMode) {
      // Simulate upload delay
      await Future.delayed(const Duration(milliseconds: 1000));

      // Return mock URL
      final mockUrl = '${AppConfig.r2PublicUrl}/$filename';
      return UploadResult.ok(mockUrl);
    }

    // Real R2 upload implementation
    // Note: This requires either:
    // 1. A backend server that handles the R2 upload
    // 2. Direct R2 API integration with signed URLs

    try {
      if (AppConfig.r2UploadEndpoint.isEmpty) {
        return UploadResult.failure(
          'R2 upload endpoint not configured. '
          'Please set r2UploadEndpoint in config.dart or use mock mode.',
        );
      }

      // Prepare multipart form data
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(image.path, filename: filename),
        'slot': slot,
      });

      // Upload to backend
      final response = await _dio.post(
        AppConfig.r2UploadEndpoint,
        data: formData,
      );

      if (response.statusCode == 200) {
        final url = response.data['url'] as String?;
        if (url != null) {
          return UploadResult.ok(url);
        }
        return UploadResult.failure('No URL in response');
      } else {
        return UploadResult.failure('Upload failed: ${response.data}');
      }
    } on DioException catch (e) {
      return UploadResult.failure(_handleDioError(e));
    } catch (e) {
      return UploadResult.failure('Upload error: $e');
    }
  }

  /// Get the public URL for a slot's image
  String getSlotImageUrl(int slot) {
    if (slot < 1 || slot > 3) return '';
    final filename = AppConfig.slotFilenames[slot - 1];
    return '${AppConfig.r2PublicUrl}/$filename';
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Upload timeout. Check your internet connection.';
      case DioExceptionType.receiveTimeout:
        return 'Server response timeout.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to upload server.';
      default:
        return e.message ?? 'Upload error occurred';
    }
  }
}
