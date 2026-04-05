import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/lego_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _resolved = false;
  bool _invalidHintShown = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractMac(String raw) {
    final trimmed = raw.trim();

    final separated = RegExp(
      r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}',
    ).firstMatch(trimmed);
    if (separated != null) {
      return separated.group(0)!.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    }

    final plain = RegExp(r'\b[0-9A-Fa-f]{12}\b').firstMatch(trimmed);
    if (plain != null) {
      return plain.group(0)!.toUpperCase();
    }

    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_resolved || !mounted) return;

    final rawValue =
        capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .firstWhere(
              (v) => v.trim().isNotEmpty,
              orElse: () => '',
            );

    if (rawValue.isEmpty) return;

    final mac = _extractMac(rawValue);
    if (mac == null) {
      if (!_invalidHintShown) {
        _invalidHintShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code 內容不是有效 MAC Address，請重新掃描'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _resolved = true;
    Navigator.of(context).pop(mac);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LegoColors.black,
      appBar: AppBar(
        title: Text(
          '掃描裝置 QR Code',
          style: LegoTypography.titleMedium.copyWith(color: LegoColors.white),
        ),
        backgroundColor: LegoColors.primary,
        iconTheme: const IconThemeData(color: LegoColors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: LegoColors.yellow, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '請將電子紙上的 MAC QR Code 放入框內，掃描後會自動帶入。',
                textAlign: TextAlign.center,
                style: LegoTypography.bodyMedium.copyWith(
                  color: LegoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
