import 'package:flutter/material.dart';
import '../theme/lego_theme.dart';

/// Button types for LegoButton
enum LegoButtonType {
  primary, // Blue - main actions
  secondary, // Yellow - secondary actions
  danger, // Red - destructive actions
}

/// A LEGO brick-style button with press animation.
///
/// Features:
/// - Three color variants (primary, secondary, danger)
/// - Press animation (scale + translate)
/// - Optional leading icon
/// - Loading state with spinner
class LegoButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final LegoButtonType type;
  final bool isLoading;
  final IconData? icon;
  final bool expanded;

  const LegoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = LegoButtonType.primary,
    this.isLoading = false,
    this.icon,
    this.expanded = true,
  });

  @override
  State<LegoButton> createState() => _LegoButtonState();
}

class _LegoButtonState extends State<LegoButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _translateAnimation;

  bool _isPressed = false;

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

    _translateAnimation = Tween<double>(
      begin: 0.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case LegoButtonType.primary:
        return LegoColors.blue;
      case LegoButtonType.secondary:
        return LegoColors.yellow;
      case LegoButtonType.danger:
        return LegoColors.red;
    }
  }

  Color get _textColor {
    switch (widget.type) {
      case LegoButtonType.primary:
      case LegoButtonType.danger:
        return LegoColors.white;
      case LegoButtonType.secondary:
        return LegoColors.black;
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: isDisabled ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _translateAnimation.value),
            child: Transform.scale(scale: _scaleAnimation.value, child: child),
          );
        },
        child: Container(
          width: widget.expanded ? double.infinity : null,
          padding: const EdgeInsets.symmetric(
            horizontal: LegoSpacing.md,
            vertical: LegoSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color:
                isDisabled
                    ? _backgroundColor.withValues(alpha: 0.5)
                    : _backgroundColor,
            borderRadius: BorderRadius.circular(LegoSpacing.borderRadius),
            boxShadow: _isPressed ? LegoShadows.pressed : LegoShadows.raised,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _lighten(_backgroundColor, 0.1),
                _backgroundColor,
                _darken(_backgroundColor, 0.1),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: Row(
            mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_textColor),
                  ),
                ),
                const SizedBox(width: LegoSpacing.xs),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, color: _textColor, size: 18),
                const SizedBox(width: LegoSpacing.xs),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: LegoTypography.labelLarge.copyWith(
                    color: _textColor,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
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
