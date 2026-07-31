import 'package:flutter/material.dart';

/// Палитра для тёмного "неонового" редизайна — используется поверх
/// динамической цветовой схемы Material 3, только там, где нужен именно
/// фирменный премиальный вид (главный дашборд, сторис), а не во всём
/// приложении целиком.
class NeonColors {
  NeonColors._();

  static const bgDeep = Color(0xFF07090D);
  static const bgSurface = Color(0xFF11141C);
  static const glassBorder = Color(0x33FFFFFF);

  static const emerald = Color(0xFF00E5A0);
  static const emeraldDim = Color(0xFF0B3B33);
  static const rose = Color(0xFFFF5C7A);
  static const roseDim = Color(0xFF3A1420);
  static const graphite = Color(0xFF5B6472);
  static const cyan = Color(0xFF3CD3FF);
  static const violet = Color(0xFF8B7CFF);

  /// Цвет свечения фона в зависимости от знака прибыли/убытка
  static Color glowFor(double profit) {
    if (profit > 0.01) return emerald;
    if (profit < -0.01) return rose;
    return graphite;
  }
}
