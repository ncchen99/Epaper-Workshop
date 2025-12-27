import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';
import 'lego_status_chip.dart';

/// A LEGO-style top bar / app bar.
///
/// Features:
/// - Title styled like printed text on a LEGO brick
/// - Optional status chip on the right
/// - LEGO red background by default
class LegoTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final ConnectionStatus? connectionStatus;
  final List<Widget>? actions;

  const LegoTopBar({
    super.key,
    required this.title,
    this.connectionStatus,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: LegoColors.red,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _lighten(LegoColors.red, 0.1),
            LegoColors.red,
            _darken(LegoColors.red, 0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Container(
        height: kToolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: LegoSpacing.md),
        child: Row(
          children: [
            // LEGO logo image (enlarged, no title)
            Image.asset(
              'assets/images/icon/lego.png',
              height: 48,
              width: 48,
              fit: BoxFit.contain,
            ),

            // Spacer to push status chip to the right
            const Spacer(),

            // Status chip
            if (connectionStatus != null)
              LegoStatusChip(status: connectionStatus!),

            // Additional actions
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
