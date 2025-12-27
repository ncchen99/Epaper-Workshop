import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';

/// A LEGO brick-style card container with studs on top.
///
/// Features:
/// - Rounded corners like LEGO bricks
/// - Optional studs on top edge
/// - Plastic-like highlight gradient
/// - Raised shadow effect
class LegoCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final int studCount;
  final bool showStuds;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const LegoCard({
    super.key,
    required this.child,
    this.color = LegoColors.yellow,
    this.studCount = 4,
    this.showStuds = true,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.all(LegoSpacing.sm),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
        boxShadow: LegoShadows.raised,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(color, 0.1), color, _darken(color, 0.05)],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
          // Plastic highlight on top edge
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Colors.white.withValues(alpha: 0.15), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Studs inside the card at the top
            if (showStuds)
              Container(
                padding: const EdgeInsets.only(top: LegoSpacing.md),
                child: SizedBox(
                  height: LegoSpacing.studDiameter,
                  child: CustomPaint(
                    size: Size(double.infinity, LegoSpacing.studDiameter),
                    painter: LegoStudPainter(
                      baseColor: _darken(color, 0.05),
                      studCount: studCount,
                    ),
                  ),
                ),
              ),

            // Main content with padding
            Container(
              padding: padding ?? const EdgeInsets.all(LegoSpacing.md),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  /// Lighten a color by a percentage
  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Darken a color by a percentage
  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
