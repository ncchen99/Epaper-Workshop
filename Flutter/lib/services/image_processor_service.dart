import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

/// Result of image processing
class ImageProcessResult {
  final bool success;
  final File? processedFile;
  final String? error;
  final int? originalWidth;
  final int? originalHeight;
  final int? finalWidth;
  final int? finalHeight;

  const ImageProcessResult({
    required this.success,
    this.processedFile,
    this.error,
    this.originalWidth,
    this.originalHeight,
    this.finalWidth,
    this.finalHeight,
  });

  factory ImageProcessResult.ok(
    File file, {
    int? originalWidth,
    int? originalHeight,
    int? finalWidth,
    int? finalHeight,
  }) => ImageProcessResult(
    success: true,
    processedFile: file,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    finalWidth: finalWidth,
    finalHeight: finalHeight,
  );

  factory ImageProcessResult.failure(String error) =>
      ImageProcessResult(success: false, error: error);
}

/// Service for processing images for E-Paper display.
///
/// Processing steps:
/// 1. Check aspect ratio - if wider than tall, rotate 90 degrees
/// 2. Resize to fit within 400x600 (maintaining aspect ratio)
/// 3. Crop to exactly 400x600 (center crop)
/// 4. Encode as JPEG baseline format
class ImageProcessorService {
  /// Target dimensions for E-Paper display
  static const int targetWidth = AppConfig.targetWidth;
  static const int targetHeight = AppConfig.targetHeight;
  static const double targetAspectRatio = targetWidth / targetHeight; // 0.667

  /// Process an image file for E-Paper display
  ///
  /// Returns a new file with the processed image (JPEG baseline format)
  Future<ImageProcessResult> processImage(File imageFile) async {
    try {
      // Read the image file
      final bytes = await imageFile.readAsBytes();
      final result = await compute(
        _processImageOnWorker,
        <String, Object>{
          'bytes': bytes,
          'targetWidth': targetWidth,
          'targetHeight': targetHeight,
          'jpegQuality': AppConfig.jpegQuality,
        },
      );

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as String? ?? 'Image processing failed';
        return ImageProcessResult.failure(error);
      }

      final jpegBytes = result['jpegBytes'] as Uint8List?;
      if (jpegBytes == null || jpegBytes.isEmpty) {
        return ImageProcessResult.failure('Image processing failed');
      }

      final originalWidth = result['originalWidth'] as int?;
      final originalHeight = result['originalHeight'] as int?;

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(tempDir.path, 'epaper_$timestamp.jpg');
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(jpegBytes, flush: true);

      return ImageProcessResult.ok(
        outputFile,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        finalWidth: targetWidth,
        finalHeight: targetHeight,
      );
    } catch (e) {
      return ImageProcessResult.failure('Image processing error: $e');
    }
  }

  /// Process image from bytes (useful for in-memory images)
  Future<ImageProcessResult> processImageFromBytes(Uint8List bytes) async {
    try {
      // Save bytes to temp file first
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempPath = path.join(tempDir.path, 'temp_$timestamp.tmp');
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      // Process the temp file
      final result = await processImage(tempFile);

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      return result;
    } catch (e) {
      return ImageProcessResult.failure('Image processing error: $e');
    }
  }

  /// Validate that an image meets the E-Paper display requirements
  static bool validateImage(File imageFile) {
    try {
      final bytes = imageFile.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) return false;

      // Check if it's the correct dimensions
      return image.width == targetWidth && image.height == targetHeight;
    } catch (e) {
      return false;
    }
  }

  /// Get image dimensions without full decode
  Future<(int width, int height)?> getImageDimensions(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return (image.width, image.height);
    } catch (e) {
      return null;
    }
  }
}

Map<String, Object> _processImageOnWorker(Map<String, Object> payload) {
  try {
    final bytes = payload['bytes'] as Uint8List;
    final targetWidth = payload['targetWidth'] as int;
    final targetHeight = payload['targetHeight'] as int;
    final jpegQuality = payload['jpegQuality'] as int;

    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      return <String, Object>{
        'success': false,
        'error': 'Failed to decode image',
      };
    }

    final originalWidth = image.width;
    final originalHeight = image.height;

    if (image.width > image.height) {
      image = img.copyRotate(image, angle: 90);
    }

    image = _resizeToFillImage(image, targetWidth, targetHeight);
    image = _centerCropImage(image, targetWidth, targetHeight);

    final jpegBytes = Uint8List.fromList(
      img.encodeJpg(image, quality: jpegQuality),
    );

    return <String, Object>{
      'success': true,
      'jpegBytes': jpegBytes,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
    };
  } catch (e) {
    return <String, Object>{
      'success': false,
      'error': 'Image processing error: $e',
    };
  }
}

img.Image _resizeToFillImage(img.Image source, int targetW, int targetH) {
  final sourceAspect = source.width / source.height;
  final targetAspect = targetW / targetH;

  int newWidth;
  int newHeight;

  if (sourceAspect > targetAspect) {
    newHeight = targetH;
    newWidth = (source.width * (targetH / source.height)).round();
  } else {
    newWidth = targetW;
    newHeight = (source.height * (targetW / source.width)).round();
  }

  return img.copyResize(
    source,
    width: newWidth,
    height: newHeight,
    interpolation: img.Interpolation.linear,
  );
}

img.Image _centerCropImage(img.Image source, int targetW, int targetH) {
  final x = (source.width - targetW) ~/ 2;
  final y = (source.height - targetH) ~/ 2;

  return img.copyCrop(
    source,
    x: x > 0 ? x : 0,
    y: y > 0 ? y : 0,
    width: targetW,
    height: targetH,
  );
}
