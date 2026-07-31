import 'package:flutter/material.dart';
import 'tokens.dart';

/// Переход между экранами: контент не «выезжает» целиком, а слегка
/// приподнимается и проявляется — спокойнее, чем стандартный Android-переход,
/// и заметно быстрее ощущается.
class FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppCurves.enter);
    final exit = CurvedAnimation(parent: secondaryAnimation, curve: AppCurves.smooth);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
        child: FadeTransition(
          // Уходящий экран не просто исчезает, а слегка гаснет — это создаёт
          // ощущение глубины стопки экранов.
          opacity: Tween<double>(begin: 1, end: 0.55).animate(exit),
          child: child,
        ),
      ),
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData build(Color seed, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final scheme = isDark
        ? base.copyWith(
            primary: AppGradient.lighten(AppGradient.saturate(seed, 0.25), 0.22),
            surface: AppColors.darkSurface,
            surfaceContainerLowest: AppColors.darkBg,
            surfaceContainerLow: AppColors.darkSurface,
            surfaceContainer: AppColors.darkSurfaceHigh,
            surfaceContainerHigh: AppColors.darkSurfaceHigh,
            surfaceContainerHighest: AppColors.darkSurfaceTop,
            outlineVariant: AppColors.darkBorder,
          )
        : base.copyWith(
            primary: AppGradient.saturate(AppGradient.darken(seed, 0.02), 0.1),
            surface: AppColors.lightSurface,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: AppColors.lightSurface,
            surfaceContainer: AppColors.lightSurfaceHigh,
            surfaceContainerHigh: AppColors.lightSurfaceHigh,
            surfaceContainerHighest: AppColors.lightSurfaceTop,
            outlineVariant: AppColors.lightBorder,
          );

    final onSurface = isDark ? Colors.white : const Color(0xFF0C1220);
    final dim = isDark ? AppColors.darkTextDim : AppColors.lightTextDim;

    final baseTheme = Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(bodyColor: onSurface, displayColor: onSurface);

    final textTheme = baseTheme.copyWith(
          displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: onSurface),
          headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: onSurface),
          headlineSmall: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: onSurface),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: onSurface),
          titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: onSurface),
          bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: onSurface),
          bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: onSurface),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: dim),
          labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: dim),
        );

    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.sm),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      canvasColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: onSurface, size: 22),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: onSurface),
      listTileTheme: ListTileThemeData(
        iconColor: dim,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: dim, fontWeight: FontWeight.w500),
        labelStyle: TextStyle(color: dim, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13.5),
        prefixIconColor: dim,
        suffixIconColor: dim,
        border: border(Colors.transparent),
        enabledBorder: border(isDark ? AppColors.darkBorder : AppColors.lightBorder),
        focusedBorder: border(scheme.primary, 1.6),
        errorBorder: border(AppColors.negative),
        focusedErrorBorder: border(AppColors.negative, 1.6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary.withOpacity(isDark ? 0.22 : 0.14),
        side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.xl)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder, width: 1.2),
          foregroundColor: onSurface,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: dim),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceTop : const Color(0xFF161D2B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
        insetPadding: const EdgeInsets.all(16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.darkSurfaceHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
        textStyle: textTheme.bodyMedium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(
            BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isDark ? Colors.white12 : Colors.black12,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceTop : const Color(0xFF161D2B),
          borderRadius: AppRadius.all(AppRadius.xs),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
