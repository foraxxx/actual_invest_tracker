import 'dart:async';
import 'storage_service.dart';
import 'backup_service.dart';
import 'backup_settings_service.dart';
import 'manual_price_service.dart';
import 'currency_service.dart';
import 'sector_service.dart';
import 'favorites_service.dart';
import 'logo_service.dart';

/// Автоматически сохраняет JSON-бэкап в папку, указанную в настройках,
/// при каждом изменении данных — без участия пользователя. Слушает версии
/// всех источников, которые входят в бэкап (сделки/доходы/планы/депозиты,
/// ручные цены, курсы валют, секторы, избранное, логотипы) и ждёт короткую
/// паузу после последнего изменения (дебаунс), чтобы не писать файл на
/// каждую отдельную мелкую правку, если их несколько подряд.
///
/// Бэкапит только АКТИВНЫЙ на момент сохранения портфель (как и ручной
/// экспорт) — один и тот же файл перезаписывается, а не копится.
class AutoBackupService {
  static Timer? _debounce;
  static bool _attached = false;

  static void attach() {
    if (_attached) return;
    _attached = true;
    StorageService.dataVersion.addListener(_onChange);
    ManualPriceService.version.addListener(_onChange);
    CurrencyService.version.addListener(_onChange);
    SectorService.version.addListener(_onChange);
    FavoritesService.version.addListener(_onChange);
    LogoService.version.addListener(_onChange);
  }

  static void _onChange() {
    if (!BackupSettingsService.enabled) return;
    final path = BackupSettingsService.folderPath;
    if (path == null) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () async {
      final error = await BackupService.saveToFolder(path);
      if (error == null) {
        await BackupSettingsService.markBackedUp();
      } else {
        await BackupSettingsService.markError(error);
      }
    });
  }

  /// Разовый запуск — при старте приложения, при возврате в приложение и
  /// при сворачивании/закрытии (см. AppLifecycleListener в main.dart), если
  /// автосохранение включено. Раньше срабатывало только на холодный запуск
  /// процесса — а обычное "свернуть/открыть заново" на Android и iOS НЕ
  /// перезапускает процесс, поэтому бэкап казался "не работающим" при входе
  /// и выходе из приложения.
  static Future<void> runNowIfEnabled() async {
    if (!BackupSettingsService.enabled) return;
    final path = BackupSettingsService.folderPath;
    if (path == null) return;
    final error = await BackupService.saveToFolder(path);
    if (error == null) {
      await BackupSettingsService.markBackedUp();
    } else {
      await BackupSettingsService.markError(error);
    }
  }
}
