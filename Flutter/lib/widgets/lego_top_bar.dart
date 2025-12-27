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
            // LEGO logo placeholder (optional studs)
            _buildStuds(2),
            const SizedBox(width: LegoSpacing.sm),

            // Title
            Expanded(
              child: Text(
                title,
                style: LegoTypography.titleLarge.copyWith(
                  color: LegoColors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

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

  Widget _buildStuds(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (index) {
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _darken(LegoColors.red, 0.1),
            border: Border.all(
              color: LegoColors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                offset: const Offset(0, 1),
                blurRadius: 1,
              ),
            ],
          ),
        );
      }),
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
