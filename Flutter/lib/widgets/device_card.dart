import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/lego_theme.dart';

/// 裝置卡片元件
///
/// 顯示一台已綁定的 E-Paper 裝置資訊，包含：
/// - MAC Address
/// - 暱稱
/// - 最後狀態
/// - 刪除按鈕
class DeviceCard extends StatelessWidget {
  final EpaperDevice device;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const DeviceCard({
    super.key,
    required this.device,
    this.isSelected = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: LegoSpacing.xs),
        padding: const EdgeInsets.all(LegoSpacing.md),
        decoration: BoxDecoration(
          color: LegoColors.white,
          borderRadius: BorderRadius.circular(LegoSpacing.sm),
          border: Border.all(
            color:
                isSelected
                    ? LegoColors.primary.withValues(alpha: 0.7)
                    : LegoColors.backgroundGray,
            width: isSelected ? 2 : 1,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: LegoColors.primary.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                    ...LegoShadows.raised,
                  ]
                  : [],
        ),
        child: Row(
          children: [
            // 裝置圖示
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getStatusColor().withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getStatusIcon(), color: _getStatusColor(), size: 20),
            ),
            const SizedBox(width: LegoSpacing.md),

            // 裝置資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: LegoTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.formattedMac,
                    style: LegoTypography.bodyMedium.copyWith(
                      color: LegoColors.darkGray,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  if (device.lastStatus != null) ...[
                    const SizedBox(height: 2),
                    _buildStatusChip(),
                  ],
                ],
              ),
            ),

            // 選中指示 / 刪除按鈕
            if (isSelected)
              Icon(Icons.check_circle, color: LegoColors.primary, size: 20)
            else if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: LegoColors.darkGray,
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getStatusIcon(), color: _getStatusColor(), size: 12),
          const SizedBox(width: 4),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: _getStatusColor(),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (device.lastStatus) {
      case 'online':
      case 'success':
        return Icons.check_circle;
      case 'downloading':
      case 'decoding':
      case 'displaying':
      case 'queued':
        return Icons.sync;
      case 'error':
        return Icons.error;
      case 'busy':
        return Icons.schedule;
      default:
        return Icons.tablet_android;
    }
  }

  String _getStatusText() {
    switch (device.lastStatus) {
      case 'online':
        return 'Ready';
      case 'success':
        return 'Success';
      case 'downloading':
        return 'Downloading';
      case 'decoding':
        return 'Decoding';
      case 'displaying':
        return 'Displaying';
      case 'queued':
        return 'Queued';
      case 'error':
        return 'Error';
      case 'busy':
        return 'Busy';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor() {
    switch (device.lastStatus) {
      case 'online':
      case 'success':
        return LegoColors.success;
      case 'downloading':
      case 'decoding':
      case 'displaying':
      case 'queued':
        return LegoColors.warning;
      case 'error':
      case 'busy':
        return LegoColors.error;
      default:
        return LegoColors.darkGray;
    }
  }
}
