import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Cloudflare R2 上傳服務
///
/// 使用 S3 compatible API 將處理後的圖片上傳至 Cloudflare R2，
/// 並回傳公開存取的 URL。
class R2UploadService {
  final Dio _dio = Dio();
  static const String _region = 'auto';
  static const String _service = 's3';

  String get _accessKeyId => dotenv.env['R2_ACCESS_KEY_ID'] ?? '';
  String get _secretAccessKey => dotenv.env['R2_SECRET_ACCESS_KEY'] ?? '';
  String get _endpointUrl => dotenv.env['R2_ENDPOINT_URL'] ?? '';
  String get _bucketName => dotenv.env['R2_BUCKET_NAME'] ?? '';
  String get _publicUrl => dotenv.env['R2_PUBLIC_URL'] ?? '';
  String get _endpointBaseUrl =>
      _endpointUrl.endsWith('/')
          ? _endpointUrl.substring(0, _endpointUrl.length - 1)
          : _endpointUrl;

  /// 上傳圖片到 R2
  ///
  /// [imageFile] - 已處理好的圖片檔案（JPEG）
  /// [filename] - 上傳後的檔案名稱（例如 "AABBCC112233_1234567890.jpg"）
  ///
  /// 回傳公開存取 URL
  Future<String> uploadImage(File imageFile, String filename) async {
    try {
      if (_accessKeyId.isEmpty ||
          _secretAccessKey.isEmpty ||
          _endpointUrl.isEmpty ||
          _bucketName.isEmpty ||
          _publicUrl.isEmpty) {
        throw Exception(
          'R2 config is missing in .env. Required keys: '
          'R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT_URL, '
          'R2_BUCKET_NAME, R2_PUBLIC_URL',
        );
      }

      final bytes = await imageFile.readAsBytes();
      final payloadHash = _sha256Hex(bytes);

      // 使用 S3-compatible PUT Object API（Cloudflare R2）
      final objectKey = filename;
      final encodedKey = _encodeObjectKey(objectKey);
      final url = '$_endpointBaseUrl/$_bucketName/$encodedKey';
      final amzDate = _getAmzDate();
      final dateShort = amzDate.substring(0, 8);
      final host = Uri.parse(_endpointBaseUrl).host;

      final signed = _buildSigV4(
        method: 'PUT',
        canonicalUri: '/$_bucketName/$encodedKey',
        host: host,
        contentType: 'image/jpeg',
        payloadHash: payloadHash,
        amzDate: amzDate,
        dateShort: dateShort,
      );

      final response = await _dio.put(
        url,
        data: bytes,
        options: Options(
          headers: {
            ...signed,
            'Content-Type': 'image/jpeg',
            'Content-Length': bytes.length.toString(),
          },
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final publicUrl = '$_publicUrl/$objectKey';
        debugPrint('R2 Upload success: $publicUrl');
        return publicUrl;
      } else {
        final body = response.data?.toString() ?? '(empty body)';
        throw Exception('R2 upload failed: HTTP ${response.statusCode}, body: $body');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data?.toString();
      throw Exception('R2 upload error: ${e.message}, status: $status, body: $body');
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

  // ---- AWS Signature V4 ----

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
    return sha256.convert(data).toString();
  }

  List<int> _hmacSha256Bytes(List<int> key, String value) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(value)).bytes;
  }

  String _hmacSha256Hex(List<int> key, String value) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(value)).toString();
  }

  String _encodeObjectKey(String objectKey) {
    return objectKey
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
  }

  Map<String, String> _buildSigV4({
    required String method,
    required String canonicalUri,
    required String host,
    required String contentType,
    required String payloadHash,
    required String amzDate,
    required String dateShort,
  }) {
    const signedHeaders =
        'content-type;host;x-amz-content-sha256;x-amz-date';

    final canonicalHeaders =
        'content-type:$contentType\n'
        'host:$host\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$amzDate\n';

    final canonicalRequest =
        '$method\n'
        '$canonicalUri\n'
        '\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';

    final credentialScope =
        '$dateShort/$_region/$_service/aws4_request';

    final stringToSign =
        'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '${_sha256Hex(utf8.encode(canonicalRequest))}';

    final kDate = _hmacSha256Bytes(
      utf8.encode('AWS4$_secretAccessKey'),
      dateShort,
    );
    final kRegion = _hmacSha256Bytes(kDate, _region);
    final kService = _hmacSha256Bytes(kRegion, _service);
    final kSigning = _hmacSha256Bytes(kService, 'aws4_request');
    final signature = _hmacSha256Hex(kSigning, stringToSign);

    final authorization =
        'AWS4-HMAC-SHA256 '
        'Credential=$_accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    return {
      'Authorization': authorization,
      'Host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
    };
  }
}
