import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';

/// A LEGO-style image tile for displaying selectable images.
///
/// Features:
/// - Selected state with highlighted border and studs
/// - Unselected state with subtle opacity
/// - Tap animation
/// - Optional 90-degree counter-clockwise rotation for portrait images
class LegoImageTile extends StatefulWidget {
  final ImageProvider image;
  final bool isSelected;
  final VoidCallback onTap;
  final String? label;

  /// If true, rotates the image 90 degrees counter-clockwise
  final bool rotateLeft;

  const LegoImageTile({
    super.key,
    required this.image,
    required this.isSelected,
    required this.onTap,
    this.label,
    this.rotateLeft = false,
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
    final borderColor =
        widget.isSelected ? LegoColors.blue : LegoColors.backgroundGray;
    final borderWidth = widget.isSelected ? 3.0 : 2.0;
    final studColor =
        widget.isSelected ? LegoColors.blue : LegoColors.backgroundGray;

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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: studColor,
            borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow:
                widget.isSelected
                    ? LegoShadows.selectedGlow(LegoColors.blue)
                    : LegoShadows.raised,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Studs on top (inside card)
              Container(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(color: studColor),
                child: CustomPaint(
                  size: const Size(double.infinity, 12),
                  painter: LegoStudPainter(baseColor: studColor, studCount: 3),
                ),
              ),

              // Image - use Expanded to fill available space
              Expanded(
                child: ClipRRect(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: widget.isSelected ? 1.0 : 0.8,
                    child:
                        widget.rotateLeft
                            ? RotatedBox(
                              quarterTurns: 3, // 向左轉 90 度 (270度順時針)
                              child: Image(
                                image: widget.image,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            )
                            : Image(
                              image: widget.image,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                  ),
                ),
              ),

              // Optional label
              if (widget.label != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: LegoSpacing.xs,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        widget.isSelected
                            ? LegoColors.blue
                            : LegoColors.backgroundGray,
                  ),
                  child: Text(
                    widget.label!,
                    style: LegoTypography.labelMedium.copyWith(
                      color:
                          widget.isSelected
                              ? LegoColors.white
                              : LegoColors.black,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
