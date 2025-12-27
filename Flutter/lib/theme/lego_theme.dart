import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LEGO-style Design System
///
/// This theme provides colors, typography, spacing, and styling
/// that mimics the look and feel of LEGO bricks.

// ===========================================
// LEGO Colors
// ===========================================

class LegoColors {
  LegoColors._();

  // Primary LEGO Colors
  static const Color red = Color(0xFFE3000B);
  static const Color yellow = Color(0xFFFFD500);
  static const Color blue = Color(0xFF0055BF);
  static const Color green = Color(0xFF00852B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF1B1B1B);

  // Secondary Colors
  static const Color orange = Color(0xFFFF6D00);
  static const Color brightGreen = Color(0xFF58AB41);

  // Background Colors (like LEGO baseplates)
  static const Color backgroundLight = Color(0xFFF5F5DC); // Beige/cream
  static const Color backgroundGray = Color(0xFFE0E0E0);
  static const Color surfaceWhite = Color(0xFFFAFAFA);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
  static const Color info = Color(0xFF42A5F5);

  // Stud Colors (for highlights/shadows)
  static const Color studHighlight = Color(0x40FFFFFF);
  static const Color studShadow = Color(0x30000000);
}

// ===========================================
// LEGO Spacing & Sizing
// ===========================================

class LegoSpacing {
  LegoSpacing._();

  // Base unit (like a LEGO stud width)
  static const double unit = 8.0;

  // Common spacings
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Stud dimensions
  static const double studDiameter = 16.0;
  static const double studHeight = 4.0;
  static const double studSpacing = 8.0;

  // Border radius (rounded like LEGO bricks)
  static const double borderRadius = 12.0;
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusLarge = 16.0;
}

// ===========================================
// LEGO Shadows
// ===========================================

class LegoShadows {
  LegoShadows._();

  /// Standard shadow for raised elements
  static List<BoxShadow> get raised => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      offset: const Offset(0, 4),
      blurRadius: 8,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
  ];

  /// Pressed/depressed shadow (for button press states)
  static List<BoxShadow> get pressed => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  /// Selected item glow
  static List<BoxShadow> selectedGlow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.4),
      offset: Offset.zero,
      blurRadius: 12,
      spreadRadius: 2,
    ),
    ...raised,
  ];
}

// ===========================================
// LEGO Typography
// ===========================================

class LegoTypography {
  LegoTypography._();

  /// Get the LEGO-style font (Fredoka One - rounded, playful but not too cartoonish)
  static final TextStyle _baseStyle = GoogleFonts.fredoka();

  static TextStyle get displayLarge => _baseStyle.copyWith(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static TextStyle get displayMedium =>
      _baseStyle.copyWith(fontSize: 24, fontWeight: FontWeight.w600);

  static TextStyle get titleLarge =>
      _baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.w500);

  static TextStyle get titleMedium =>
      _baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w500);

  static TextStyle get bodyLarge =>
      _baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w400);

  static TextStyle get bodyMedium =>
      _baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w400);

  static TextStyle get labelLarge => _baseStyle.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static TextStyle get labelMedium =>
      _baseStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w500);
}

// ===========================================
// LEGO Stud Painter
// ===========================================

/// Custom painter for drawing LEGO studs
class LegoStudPainter extends CustomPainter {
  final Color baseColor;
  final int studCount;

  LegoStudPainter({required this.baseColor, required this.studCount});

  @override
  void paint(Canvas canvas, Size size) {
    final studRadius = LegoSpacing.studDiameter / 2;
    final totalWidth =
        studCount * LegoSpacing.studDiameter +
        (studCount - 1) * LegoSpacing.studSpacing;
    final startX = (size.width - totalWidth) / 2 + studRadius;
    final centerY = size.height / 2;

    for (int i = 0; i < studCount; i++) {
      final centerX =
          startX + i * (LegoSpacing.studDiameter + LegoSpacing.studSpacing);
      final center = Offset(centerX, centerY);

      // Main stud body
      final studPaint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, studRadius, studPaint);

      // Top highlight (lighter)
      final highlightPaint = Paint()
        ..color = LegoColors.studHighlight
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: studRadius - 1),
        -2.5,
        1.8,
        false,
        highlightPaint,
      );

      // Bottom shadow (darker)
      final shadowPaint = Paint()
        ..color = LegoColors.studShadow
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: studRadius - 1),
        0.5,
        1.8,
        false,
        shadowPaint,
      );

      // Inner circle for depth
      final innerPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, studRadius * 0.6, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LegoStudPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor ||
        oldDelegate.studCount != studCount;
  }
}

// ===========================================
// LEGO Theme Data
// ===========================================

class LegoTheme {
  LegoTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: LegoColors.red,
    scaffoldBackgroundColor: LegoColors.backgroundLight,
    colorScheme: ColorScheme.fromSeed(
      seedColor: LegoColors.red,
      brightness: Brightness.light,
      surface: LegoColors.surfaceWhite,
    ),
    textTheme: TextTheme(
      displayLarge: LegoTypography.displayLarge,
      displayMedium: LegoTypography.displayMedium,
      titleLarge: LegoTypography.titleLarge,
      titleMedium: LegoTypography.titleMedium,
      bodyLarge: LegoTypography.bodyLarge,
      bodyMedium: LegoTypography.bodyMedium,
      labelLarge: LegoTypography.labelLarge,
      labelMedium: LegoTypography.labelMedium,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: LegoColors.red,
      foregroundColor: LegoColors.white,
      elevation: 0,
      titleTextStyle: LegoTypography.titleLarge.copyWith(
        color: LegoColors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LegoColors.blue,
        foregroundColor: LegoColors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: LegoSpacing.lg,
          vertical: LegoSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
        ),
      ),
    ),
  );
}
