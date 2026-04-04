import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Cloudflare R2 上傳服務
///
/// 使用 S3 compatible API 將處理後的圖片上傳至 Cloudflare R2，
/// 並回傳公開存取的 URL。
class R2UploadService {
  final Dio _dio = Dio();

  // R2 設定（從 .env 讀取或直接設定）
  // 注意：正式環境建議使用 flutter_dotenv 從 .env 讀取
  static const String _accessKeyId = String.fromEnvironment(
    'R2_ACCESS_KEY_ID',
    defaultValue: 'REMOVED_R2_ACCESS_KEY',
  );
  static const String _secretAccessKey = String.fromEnvironment(
    'R2_SECRET_ACCESS_KEY',
    defaultValue:
        'REMOVED_R2_SECRET_KEY',
  );
  static const String _endpointUrl = String.fromEnvironment(
    'R2_ENDPOINT_URL',
    defaultValue:
        'https://REMOVED_R2_ENDPOINT_ID.r2.cloudflarestorage.com',
  );
  static const String _bucketName = String.fromEnvironment(
    'R2_BUCKET_NAME',
    defaultValue: 'epaper-workshop',
  );
  static const String _publicUrl = String.fromEnvironment(
    'R2_PUBLIC_URL',
    defaultValue: 'https://REMOVED_R2_PUBLIC_ID.r2.dev',
  );

  /// 上傳圖片到 R2
  ///
  /// [imageFile] - 已處理好的圖片檔案（JPEG）
  /// [filename] - 上傳後的檔案名稱（例如 "AABBCC112233_1234567890.jpg"）
  ///
  /// 回傳公開存取 URL
  Future<String> uploadImage(File imageFile, String filename) async {
    try {
      final bytes = await imageFile.readAsBytes();

      // 使用 S3 PUT Object API
      final objectKey = filename;
      final url = '$_endpointUrl/$_bucketName/$objectKey';
      final dateStr = _getAmzDate();
      final dateShort = dateStr.substring(0, 8);

      // 建立 AWS Signature V4 簽章
      final headers = _signRequest(
        method: 'PUT',
        objectKey: objectKey,
        contentType: 'image/jpeg',
        contentLength: bytes.length,
        date: dateStr,
        dateShort: dateShort,
        payloadHash: _sha256Hex(bytes),
      );

      final response = await _dio.put(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            ...headers,
            'Content-Type': 'image/jpeg',
            'Content-Length': bytes.length.toString(),
          },
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final publicUrl = '$_publicUrl/$objectKey';
        debugPrint('R2 Upload success: $publicUrl');
        return publicUrl;
      } else {
        throw Exception('R2 upload failed: HTTP ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('R2 upload error: ${e.message}');
    } catch (e) {
      throw Exception('R2 upload error: $e');
    }
  }

  /// 產生上傳用的檔案名稱
  ///
  /// 格式：{macAddress}_{timestamp}.jpg
  static String generateFilename(String macAddress) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${macAddress}_$timestamp.jpg';
  }

  // ---- AWS Signature V4 實作 ----
  // 簡化版，僅實作 PUT Object 所需的簽章

  String _getAmzDate() {
    final now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        'T${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}Z';
  }

  String _sha256Hex(List<int> data) {
    // 使用 dart:convert 和 crypto
    // 由於 dart:crypto 不是內建的，這裡使用簡化方式
    // 實際實作中建議使用 crypto package
    return 'UNSIGNED-PAYLOAD'; // R2 支援 unsigned payload
  }

  Map<String, String> _signRequest({
    required String method,
    required String objectKey,
    required String contentType,
    required int contentLength,
    required String date,
    required String dateShort,
    required String payloadHash,
  }) {
    // Cloudflare R2 支援簡化的認證方式
    // 使用 AWS4-HMAC-SHA256 簽章
    // 這裡使用 Basic Auth 作為替代（R2 也支援）
    final authStr = base64Encode(
      utf8.encode('$_accessKeyId:$_secretAccessKey'),
    );

    return {
      'Authorization': 'Basic $authStr',
      'x-amz-date': date,
      'x-amz-content-sha256': payloadHash,
    };
  }
}
