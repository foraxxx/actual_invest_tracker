import 'package:flutter/material.dart';

/// "Механический" счётчик: при изменении [value] число плавно прокручивается
/// от старого значения к новому (а не просто мгновенно перерисовывается).
/// TweenAnimationBuilder сам продолжает анимацию от текущего отображаемого
/// значения к новому при каждом обновлении — отдельно хранить предыдущее
/// значение не нужно.
class RollingNumber extends StatelessWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;

  const RollingNumber({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // begin умышленно не задан: если он null, TweenAnimationBuilder сам
      // подставляет туда значение, отображавшееся на предыдущей отрисовке,
      // и анимирует от него к новому end — то есть плавно "докручивает"
      // число при каждом изменении value, без ручного хранения предыдущего.
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Text(formatter(animated), style: style);
      },
    );
  }
}
