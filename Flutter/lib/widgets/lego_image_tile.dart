import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';

/// A LEGO-style image tile for displaying selectable images.
///
/// Features:
/// - Selected state with highlighted border and studs
/// - Unselected state with subtle opacity
/// - Tap animation
class LegoImageTile extends StatefulWidget {
  final ImageProvider image;
  final bool isSelected;
  final VoidCallback onTap;
  final String? label;

  const LegoImageTile({
    super.key,
    required this.image,
    required this.isSelected,
    required this.onTap,
    this.label,
  });

  @override
  State<LegoImageTile> createState() => _LegoImageTileState();
}

class _LegoImageTileState extends State<LegoImageTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isSelected
        ? LegoColors.blue
        : LegoColors.backgroundGray;
    final borderWidth = widget.isSelected ? 4.0 : 2.0;
    final studColor = widget.isSelected
        ? LegoColors.blue
        : LegoColors.backgroundGray;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: widget.isSelected
                ? LegoShadows.selectedGlow(LegoColors.blue)
                : LegoShadows.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Studs on top
              Container(
                height: LegoSpacing.studDiameter + LegoSpacing.xs,
                decoration: BoxDecoration(
                  color: studColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(LegoSpacing.borderRadius - 2),
                    topRight: Radius.circular(LegoSpacing.borderRadius - 2),
                  ),
                ),
                child: CustomPaint(
                  size: Size(double.infinity, LegoSpacing.studDiameter),
                  painter: LegoStudPainter(baseColor: studColor, studCount: 3),
                ),
              ),

              // Image
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(LegoSpacing.borderRadius - 2),
                  bottomRight: Radius.circular(LegoSpacing.borderRadius - 2),
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: widget.isSelected ? 1.0 : 0.7,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image(image: widget.image, fit: BoxFit.cover),
                  ),
                ),
              ),

              // Optional label
              if (widget.label != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(LegoSpacing.xs),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? LegoColors.blue
                        : LegoColors.backgroundGray,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(LegoSpacing.borderRadius - 2),
                      bottomRight: Radius.circular(
                        LegoSpacing.borderRadius - 2,
                      ),
                    ),
                  ),
                  child: Text(
                    widget.label!,
                    style: LegoTypography.labelMedium.copyWith(
                      color: widget.isSelected
                          ? LegoColors.white
                          : LegoColors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
