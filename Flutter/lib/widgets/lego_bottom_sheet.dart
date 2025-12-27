import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';
import 'lego_button.dart';

/// Options for image source selection
enum ImageSource { camera, gallery }

/// A LEGO-style bottom sheet for selecting image source.
///
/// Features:
/// - Camera and Gallery options
/// - LEGO brick styling with studs
/// - Slide-up animation
class LegoBottomSheet extends StatelessWidget {
  final Function(ImageSource) onSelect;

  const LegoBottomSheet({super.key, required this.onSelect});

  /// Show the bottom sheet and return the selected source
  static Future<ImageSource?> show(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => LegoBottomSheet(
            onSelect: (source) => Navigator.of(context).pop(source),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(LegoSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar (like a LEGO connection point)
          Container(
            width: 40,
            height: 6,
            margin: const EdgeInsets.only(bottom: LegoSpacing.sm),
            decoration: BoxDecoration(
              color: LegoColors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Main sheet body
          Container(
            decoration: BoxDecoration(
              color: LegoColors.yellow,
              borderRadius: BorderRadius.circular(
                LegoSpacing.borderRadiusLarge,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _lighten(LegoColors.yellow, 0.1),
                  LegoColors.yellow,
                  _darken(LegoColors.yellow, 0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  offset: const Offset(0, -4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Studs on top
                SizedBox(
                  height:
                      LegoSpacing.studDiameter +
                      LegoSpacing.lg +
                      LegoSpacing.sm,
                  child: CustomPaint(
                    size: Size(double.infinity, LegoSpacing.studDiameter),
                    painter: LegoStudPainter(
                      baseColor: LegoColors.yellow,
                      studCount: 6,
                    ),
                  ),
                ),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LegoSpacing.lg,
                  ),
                  child: Text(
                    'Choose Image Source',
                    style: LegoTypography.titleLarge.copyWith(
                      color: LegoColors.black,
                    ),
                  ),
                ),

                const SizedBox(height: LegoSpacing.lg),

                // Options
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LegoSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      LegoButton(
                        label: 'Take Photo',
                        icon: Icons.camera_alt,
                        type: LegoButtonType.primary,
                        onPressed: () => onSelect(ImageSource.camera),
                      ),

                      const SizedBox(height: LegoSpacing.md),

                      LegoButton(
                        label: 'Choose from Gallery',
                        icon: Icons.photo_library,
                        type: LegoButtonType.secondary,
                        onPressed: () => onSelect(ImageSource.gallery),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: LegoSpacing.md),

                // Cancel button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LegoSpacing.md,
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: LegoTypography.labelLarge.copyWith(
                        color: LegoColors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: LegoSpacing.md),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
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
