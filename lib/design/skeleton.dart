import 'package:flutter/material.dart';

import 'tokens.dart';

// =============================================================================
// ЗАГОТОВКИ ЗАГРУЗКИ
// =============================================================================

/// Мягкий перелив поверх серых заготовок, пока грузятся данные.
///
/// Вместо крутящегося кружка человек сразу видит форму будущего содержимого:
/// где будет график, где строки. Экран не прыгает, когда данные приезжают, —
/// заготовка занимает то же место.
///
/// Если в системе отключена анимация, перелива нет — остаются спокойные
/// серые формы.
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) return widget.child;

    final highlight = context.isDark ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.65);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Светлая полоса проходит слева направо и уходит за край.
        final t = _c.value * 2 - 0.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, highlight, Colors.transparent],
            stops: [
              (t - 0.25).clamp(0.0, 1.0).toDouble(),
              t.clamp(0.0, 1.0).toDouble(),
              (t + 0.25).clamp(0.0, 1.0).toDouble(),
            ],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// Серый блок заготовки.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.06) : AppColors.lightSurfaceTop,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Заготовка графика: волнистая линия и подписи по краям.
class ChartSkeleton extends StatelessWidget {
  final double height;

  const ChartSkeleton({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    final color = context.isDark ? Colors.white.withOpacity(0.06) : AppColors.lightSurfaceTop;
    return Shimmer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _WavePainter(color)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;

  _WavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Условная линия графика с заливкой под ней — узнаётся с первого взгляда.
    const shape = [0.62, 0.55, 0.6, 0.45, 0.5, 0.38, 0.42, 0.3, 0.34, 0.25];
    final path = Path();
    final step = size.width / (shape.length - 1);
    for (int i = 0; i < shape.length; i++) {
      final p = Offset(i * step, shape[i] * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prev = Offset((i - 1) * step, shape[i - 1] * size.height);
        final mid = (prev.dx + p.dx) / 2;
        path.cubicTo(mid, prev.dy, mid, p.dy, p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity((color.opacity * 2.2).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}

/// Заготовка нескольких строк списка: кружок, две строки текста, сумма.
class ListSkeleton extends StatelessWidget {
  final int rows;

  const ListSkeleton({super.key, this.rows = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (int i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  const SkeletonBox(width: 34, height: 34, radius: 17),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120.0 + (i % 2) * 30, height: 11),
                        const SizedBox(height: 6),
                        const SkeletonBox(width: 80, height: 9),
                      ],
                    ),
                  ),
                  const SkeletonBox(width: 64, height: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
