import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 7)
class AppSettings extends HiveObject {
  @HiveField(0)
  int accentColorValue; // ARGB int цвета акцента

  @HiveField(1)
  bool useDarkMode; // null-логика: следуем системе, если не задано явно — храним просто bool + флаг ниже

  @HiveField(2)
  bool followSystemTheme;

  AppSettings({
    required this.accentColorValue,
    this.useDarkMode = false,
    this.followSystemTheme = true,
  });
}
