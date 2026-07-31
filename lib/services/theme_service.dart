import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/app_settings.dart';

/// Готовые палитры на выбор пользователю
class AppPalette {
  final String name;
  final Color color;
  const AppPalette(this.name, this.color);
}

const List<AppPalette> kPalettes = [
  // Первые восемь — «исторические» цвета: их значения не меняются, чтобы у
  // тех, кто уже выбрал палитру, после обновления ничего не переключилось.
  AppPalette('Изумрудный', Color(0xFF2E7D5B)),
  AppPalette('Индиго', Color(0xFF3F51B5)),
  AppPalette('Бордовый', Color(0xFFAD1457)),
  AppPalette('Янтарный', Color(0xFFE65100)),
  AppPalette('Бирюзовый', Color(0xFF00838F)),
  AppPalette('Фиолетовый', Color(0xFF6A1B9A)),
  AppPalette('Графитовый', Color(0xFF37474F)),
  AppPalette('Коралловый', Color(0xFFD84315)),
  // Новые, более насыщенные — под градиенты редизайна.
  AppPalette('Неон', Color(0xFF00D68F)),
  AppPalette('Электрик', Color(0xFF3D7BFF)),
  AppPalette('Аметист', Color(0xFF8B5CF6)),
  AppPalette('Закат', Color(0xFFFF6B4A)),
  AppPalette('Фуксия', Color(0xFFEC4899)),
  AppPalette('Лазурь', Color(0xFF06B6D4)),
];

/// Глобальное состояние темы — слушается в main.dart через ValueListenableBuilder,
/// сохраняется локально в Hive, без интернета и без БД-сервера.
class ThemeService {
  static const boxName = 'settings';
  static late Box<AppSettings> _box;

  static final ValueNotifier<Color> accentColor = ValueNotifier(kPalettes.first.color);
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  static Future<void> init() async {
    Hive.registerAdapter(AppSettingsAdapter());
    _box = await Hive.openBox<AppSettings>(boxName);

    final saved = _box.get('main');
    if (saved != null) {
      accentColor.value = Color(saved.accentColorValue);
      themeMode.value = saved.followSystemTheme
          ? ThemeMode.system
          : (saved.useDarkMode ? ThemeMode.dark : ThemeMode.light);
    } else {
      await _box.put(
        'main',
        AppSettings(accentColorValue: kPalettes.first.color.value),
      );
    }
  }

  static Future<void> setAccentColor(Color color) async {
    accentColor.value = color;
    final s = _box.get('main')!;
    s.accentColorValue = color.value;
    await s.save();
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final s = _box.get('main')!;
    s.followSystemTheme = mode == ThemeMode.system;
    s.useDarkMode = mode == ThemeMode.dark;
    await s.save();
  }
}
