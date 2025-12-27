import 'dart:io';
import '../config.dart';
import 'image_processor_service.dart';
import 'arduino_service.dart';

/// Result of an upload operation
class UploadResult {
  final bool success;
  final String? message;
  final String? error;
  final int? processedWidth;
  final int? processedHeight;

  const UploadResult({
    required this.success,
    this.message,
    this.error,
    this.processedWidth,
    this.processedHeight,
  });

  factory UploadResult.ok(
    String message, {
    int? processedWidth,
    int? processedHeight,
  }) => UploadResult(
    success: true,
    message: message,
    processedWidth: processedWidth,
    processedHeight: processedHeight,
  );

  factory UploadResult.failure(String error) =>
      UploadResult(success: false, error: error);
}

/// Service for uploading images directly to Arduino E-Paper device.
///
/// This service:
/// 1. Processes images to fit E-Paper requirements (400x600, JPEG)
/// 2. Uploads directly to Arduino via HTTP POST (no cloud storage needed)
class UploadService {
  final ImageProcessorService _imageProcessor = ImageProcessorService();
  final ArduinoService _arduinoService = ArduinoService();

  /// Upload an image file for a specific slot.
  ///
  /// [image] - The image file to upload
  /// [slot] - The slot number (1, 2, or 3) determines the filename
  ///
  /// The image will be:
  /// 1. Rotated if landscape (wider than tall)
  /// 2. Resized to fit 400x600
  /// 3. Center-cropped to exactly 400x600
  /// 4. Compressed as JPEG baseline format
  /// 5. Uploaded directly to Arduino
  ///
  /// Returns the result with success/failure status.
  Future<UploadResult> uploadImage(File image, int slot) async {
    if (slot < 1 || slot > 3) {
      return UploadResult.failure('Invalid slot: $slot. Must be 1, 2, or 3.');
    }

    if (AppConfig.mockMode) {
      // Simulate upload delay
      await Future.delayed(const Duration(milliseconds: 1500));
      return UploadResult.ok(
        'Mock: Image uploaded to slot $slot',
        processedWidth: AppConfig.targetWidth,
        processedHeight: AppConfig.targetHeight,
      );
    }

    try {
      // Step 1: Process the image to E-Paper specifications
      final processResult = await _imageProcessor.processImage(image);
      if (!processResult.success || processResult.processedFile == null) {
        return UploadResult.failure(
          processResult.error ?? 'Image processing failed',
        );
      }

      final processedFile = processResult.processedFile!;

      // Step 2: Check connection to Arduino (with fallback)
      final connected = await _arduinoService.checkConnection();
      if (!connected) {
        return UploadResult.failure(
          'Cannot connect to Arduino. Check WiFi and device power.',
        );
      }

      // Step 3: Upload directly to Arduino
      final uploadResult = await _arduinoService.uploadImage(
        slot,
        processedFile,
      );

      // Step 4: Clean up temporary processed file
      try {
        await processedFile.delete();
      } catch (_) {}

      if (uploadResult.success) {
        return UploadResult.ok(
          uploadResult.message ?? 'Image uploaded successfully',
          processedWidth: processResult.finalWidth,
          processedHeight: processResult.finalHeight,
        );
      } else {
        return UploadResult.failure(uploadResult.error ?? 'Upload failed');
      }
    } catch (e) {
      return UploadResult.failure('Upload error: $e');
    }
  }

  /// Process image only (for preview without upload)
  Future<ImageProcessResult> processImageForPreview(File image) async {
    return _imageProcessor.processImage(image);
  }

  /// Get current Arduino connection URL
  String getArduinoUrl() => _arduinoService.currentUrl;

  /// Check if using fallback IP
  bool isUsingFallbackIp() => _arduinoService.isUsingFallback;
}
