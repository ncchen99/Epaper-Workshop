import 'dart:io';
import 'dart:typed_data';
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
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        return ImageProcessResult.failure('Failed to decode image');
      }

      final originalWidth = image.width;
      final originalHeight = image.height;

      // Step 1: Check aspect ratio and rotate if needed
      // If the image is wider than tall (landscape), rotate it 90 degrees
      if (image.width > image.height) {
        image = img.copyRotate(image, angle: 90);
      }

      // Step 2: Resize to fit the target size while maintaining aspect ratio
      // We want the image to cover the target area, so we scale to fill
      image = _resizeToFill(image, targetWidth, targetHeight);

      // Step 3: Center crop to exactly 400x600
      image = _centerCrop(image, targetWidth, targetHeight);

      // Step 4: Encode as JPEG baseline format
      // The `image` package produces baseline JPEG by default
      final jpegBytes = img.encodeJpg(image, quality: AppConfig.jpegQuality);

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(tempDir.path, 'epaper_$timestamp.jpg');
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(jpegBytes);

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

  /// Resize image to fill the target dimensions (cover mode)
  ///
  /// The resulting image will be at least as large as the target in both dimensions.
  /// This ensures we can crop to the exact target size without any empty areas.
  img.Image _resizeToFill(img.Image source, int targetW, int targetH) {
    final sourceAspect = source.width / source.height;
    final targetAspect = targetW / targetH;

    int newWidth, newHeight;

    if (sourceAspect > targetAspect) {
      // Source is wider - scale by height
      newHeight = targetH;
      newWidth = (source.width * (targetH / source.height)).round();
    } else {
      // Source is taller - scale by width
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

  /// Center crop the image to the exact target dimensions
  img.Image _centerCrop(img.Image source, int targetW, int targetH) {
    // Calculate crop offset (center the crop)
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
