import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';

/// Connection status for the device
enum ConnectionStatus { connected, disconnected, sending, error }

/// A LEGO-style status chip showing device connection state.
///
/// Features:
/// - Color-coded status indicator
/// - Icon for each state
/// - Animated spinner for "sending" state
class LegoStatusChip extends StatelessWidget {
  final ConnectionStatus status;

  const LegoStatusChip({super.key, required this.status});

  Color get _backgroundColor {
    switch (status) {
      case ConnectionStatus.connected:
        return LegoColors.success;
      case ConnectionStatus.disconnected:
        return LegoColors.backgroundGray;
      case ConnectionStatus.sending:
        return LegoColors.warning;
      case ConnectionStatus.error:
        return LegoColors.error;
    }
  }

  Color get _textColor {
    switch (status) {
      case ConnectionStatus.connected:
      case ConnectionStatus.sending:
      case ConnectionStatus.error:
        return LegoColors.white;
      case ConnectionStatus.disconnected:
        return LegoColors.black;
    }
  }

  IconData get _icon {
    switch (status) {
      case ConnectionStatus.connected:
        return Icons.check_circle;
      case ConnectionStatus.disconnected:
        return Icons.cancel;
      case ConnectionStatus.sending:
        return Icons.sync;
      case ConnectionStatus.error:
        return Icons.error;
    }
  }

  String get _label {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.sending:
        return 'Sending...';
      case ConnectionStatus.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LegoSpacing.md,
        vertical: LegoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(LegoSpacing.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ConnectionStatus.sending)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_textColor),
              ),
            )
          else
            Icon(_icon, color: _textColor, size: 14),
          const SizedBox(width: LegoSpacing.xs),
          Text(
            _label,
            style: LegoTypography.labelMedium.copyWith(color: _textColor),
          ),
        ],
      ),
    );
  }
}
