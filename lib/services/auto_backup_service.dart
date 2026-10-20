import 'dart:async';
import 'budget_service.dart';
import 'appearance_service.dart';
import 'goal_service.dart';
import 'iis_service.dart';
import 'portfolio_service.dart';
import 'storage_service.dart';
import 'backup_service.dart';
import 'backup_settings_service.dart';
import 'manual_price_service.dart';
import 'currency_service.dart';
import 'sector_service.dart';
import 'favorites_service.dart';
import 'logo_service.dart';
import 'dividend_history_service.dart';

/// Автоматически сохраняет JSON-бэкап в папку, указанную в настройках,
/// при каждом изменении данных — без участия пользователя. Слушает версии
/// всех источников, которые входят в бэкап (сделки/доходы/планы/депозиты,
/// ручные цены, курсы валют, секторы, избранное, свои логотипы, история дивидендов) и ждёт короткую
/// паузу после последнего изменения (дебаунс), чтобы не писать файл на
/// каждую отдельную мелкую правку, если их несколько подряд.
///
/// Бэкапит ВСЕ портфели одним файлом (как и ручной экспорт) — один и тот же
/// файл перезаписывается, а не копится.
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
    // История дивидендов — только когда в ней появилось новое.
    DividendHistoryService.changed.addListener(_onChange);
    GoalService.version.addListener(_onChange);
    IisService.version.addListener(_onChange);
    PortfolioService.version.addListener(_onChange);
    BudgetService.version.addListener(_onChange);
    // Часть оформления тоже входит в бэкап.
    AppearanceService.version.addListener(_onChange);
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
