import 'package:flutter/material.dart';

/// Единая палитра редизайна "Aurora".
///
/// Здесь только сырые токены — цвета, радиусы, отступы, длительности.
/// Сборка темы из них — в app_theme.dart, готовые виджеты — в surfaces.dart,
/// charts.dart и fields.dart.
class AppColors {
  AppColors._();

  // --- Тёмная тема: почти чёрный космос с холодным подтоном ---
  static const darkBg = Color(0xFF05070C);
  static const darkSurface = Color(0xFF0D111A);
  static const darkSurfaceHigh = Color(0xFF151B28);
  static const darkSurfaceTop = Color(0xFF1D2434);
  static const darkBorder = Color(0x1AFFFFFF);
  static const darkTextDim = Color(0xFF8A93A6);

  // --- Светлая тема: тёплый фарфор, без «больничной» белизны ---
  static const lightBg = Color(0xFFF3F5FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFEEF1F8);
  static const lightSurfaceTop = Color(0xFFE5EAF4);
  static const lightBorder = Color(0x140B1220);
  static const lightTextDim = Color(0xFF6B7688);

  // --- Смысловые цвета (одинаковые в обеих темах, читаются везде) ---
  static const positive = Color(0xFF16D796);
  static const negative = Color(0xFFFF4D6D);
  static const warning = Color(0xFFFFB020);
  static const info = Color(0xFF3DA9FC);
  static const violet = Color(0xFF8B7CFF);
  static const cyan = Color(0xFF3CD3FF);
  static const neutral = Color(0xFF6B7688);
  static const gold = Color(0xFFFFC53D);

  /// Цвет для числа прибыли/убытка: зелёный в плюс, красный в минус,
  /// серый — если ровно ноль (чтобы «0 ₽» не выглядел как достижение).
  static Color pnl(double v) {
    if (v > 0.0001) return positive;
    if (v < -0.0001) return negative;
    return neutral;
  }

  /// Палитра для круговых/столбчатых диаграмм. Порядок подобран так, чтобы
  /// соседние сегменты всегда контрастировали друг с другом.
  static const chart = <Color>[
    Color(0xFF7C6CFF),
    Color(0xFF16D796),
    Color(0xFFFF8A5B),
    Color(0xFF3DA9FC),
    Color(0xFFFF5C93),
    Color(0xFFFFC53D),
    Color(0xFF3CD3FF),
    Color(0xFFB388FF),
    Color(0xFF00C2A8),
    Color(0xFFF06292),
  ];

  static Color chartAt(int i) => chart[i % chart.length];
}

/// Радиусы скругления. В приложении всего четыре размера — этого достаточно,
/// а единообразие важнее точной подгонки под каждый блок.
class AppRadius {
  AppRadius._();
  static const double xs = 10;
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 26;
  static const double xl = 34;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 36;
}

class AppDuration {
  AppDuration._();
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 600);
  static const chart = Duration(milliseconds: 950);
}

class AppCurves {
  AppCurves._();
  static const enter = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutBack;
  static const smooth = Curves.easeInOutCubic;
}

/// Утилиты для акцентного цвета: из одного пользовательского цвета делаем
/// градиентную пару (сам цвет + его более светлый/смещённый по тону вариант),
/// чтобы карточки и кнопки выглядели объёмно при любой выбранной палитре.
class AppGradient {
  AppGradient._();

  static Color lighten(Color c, [double amount = 0.12]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static Color darken(Color c, [double amount = 0.12]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  static Color saturate(Color c, [double amount = 0.15]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withSaturation((hsl.saturation + amount).clamp(0.0, 1.0)).toColor();
  }

  /// Родственный цвет — тот же тон, сдвинутый по кругу: даёт «живой» градиент
  /// вместо плоского перехода из цвета в его же осветлённую версию.
  static Color shiftHue(Color c, double degrees) {
    final hsl = HSLColor.fromColor(c);
    final h = (hsl.hue + degrees) % 360;
    return hsl.withHue(h < 0 ? h + 360 : h).toColor();
  }

  static List<Color> pair(Color accent) => [
        saturate(lighten(accent, 0.06), 0.18),
        saturate(shiftHue(darken(accent, 0.06), 28), 0.1),
      ];

  static LinearGradient accent(Color accent, {double opacity = 1}) {
    final p = pair(accent);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [p[0].withOpacity(opacity), p[1].withOpacity(opacity)],
    );
  }
}

extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  ColorScheme get colors => Theme.of(this).colorScheme;
  Color get accent => Theme.of(this).colorScheme.primary;

  /// Приглушённый цвет подписи — читаемый на обеих темах, в отличие от
  /// жёстко зашитого Colors.grey.
  Color get dim => isDark ? AppColors.darkTextDim : AppColors.lightTextDim;

  Color get hairline => isDark ? AppColors.darkBorder : AppColors.lightBorder;
}
