import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'neon_colors.dart';

/// "Живой" фон: два медленно дрейфующих размытых пятна света, цвет которых
/// зависит от текущего профита портфеля — изумрудное свечение при росте,
/// приглушённо-графитовое при нейтральном балансе, розовое при просадке.
/// Ставится позади контента экрана (в Stack), сам контент рисуется поверх.
class AmbientBackground extends StatefulWidget {
  final double profit;
  final Widget child;
  const AmbientBackground({super.key, required this.profit, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = NeonColors.glowFor(widget.profit);
    return Container(
      color: NeonColors.bgDeep,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value * 2 * 3.14159265;
                return Stack(
                  children: [
                    Positioned(
                      left: 40 + 60 * (0.5 + 0.5 * math.sin(t)),
                      top: -80 + 40 * math.sin(t * 0.7),
                      child: _blob(glow.withOpacity(0.35), 260),
                    ),
                    Positioned(
                      right: 20 + 50 * (0.5 + 0.5 * math.sin(t * 0.9 + 2)),
                      top: 140 + 50 * math.sin(t * 0.5 + 1),
                      child: _blob(NeonColors.cyan.withOpacity(0.16), 220),
                    ),
                  ],
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
