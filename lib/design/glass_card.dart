import 'dart:ui';
import 'package:flutter/material.dart';
import 'neon_colors.dart';

/// Карточка в стиле "матового стекла": блюр фона за карточкой + полупрозрачная
/// заливка + тонкая светящаяся рамка. Используется на переработанном
/// дашборде поверх AmbientBackground.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 24,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final glow = glowColor ?? NeonColors.emerald;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: NeonColors.glassBorder, width: 1),
            boxShadow: [
              BoxShadow(color: glow.withOpacity(0.18), blurRadius: 30, spreadRadius: -6),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
