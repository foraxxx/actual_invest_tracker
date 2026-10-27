import 'beta_service.dart';
import 'currency_service.dart';
import 'dividend_history_service.dart';
import 'manual_price_service.dart';
import 'moex_sync_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'payout_forecast_service.dart';
import 'portfolio_history_service.dart';
import 'portfolio_service.dart';
import 'sector_service.dart';
import 'storage_service.dart';
import 'iis_service.dart';
import 'tax_service.dart';

/// Запоминает результаты тяжёлых расчётов, пока не изменились исходные
/// данные: сделки, цены, курсы, выбранный портфель.
///
/// Главная перестраивается часто — от каждой новой котировки, касания графика
/// или раскрытия раздела. Без запоминания одни и те же позиции, движения
/// денег и доходности пересчитывались десятки раз за одну перерисовку.
class Memo {
  Memo._();

  static final Map<String, (int, Object?)> _cache = {};

  /// Отпечаток всех исходных данных. Меняется, как только меняется хоть
  /// что-то, от чего зависят расчёты, — тогда всё считается заново.
  static int get stamp {
    final now = DateTime.now();
    return Object.hashAll([
      StorageService.dataVersion.value,
      ManualPriceService.version.value,
      OnlinePriceService.version.value,
      CurrencyService.version.value,
      PortfolioService.version.value,
      _safe(() => PortfolioService.activeId),
      _safe(() => OnlineSettingsService.enabled),
      SectorService.version.value,
      PayoutForecastService.version.value,
      DividendHistoryService.version.value,
      BetaService.version.value,
      // Ставка налога меняет прогноз выплат (он после налога).
      TaxService.version.value,
      IisService.version.value,
      identityHashCode(MoexSyncService.marketSnapshot.value),
      identityHashCode(PortfolioHistoryService.timeline.value),
      // Расчёты «на сегодня» должны обновиться и после полуночи.
      now.year * 400 + now.month * 32 + now.day,
    ]);
  }

  /// Хранилище может быть ещё не открыто — например, в тестах расчётов.
  static Object? _safe(Object? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  /// Результат [compute] для [key] — из памяти, если исходные данные с
  /// прошлого раза не менялись.
  static T get<T>(String key, T Function() compute) {
    final s = stamp;
    final hit = _cache[key];
    if (hit != null && hit.$1 == s) return hit.$2 as T;
    final value = compute();
    // Старые записи с другим отпечатком больше не понадобятся.
    if (_cache.length > 200) _cache.removeWhere((_, v) => v.$1 != s);
    _cache[key] = (s, value);
    return value;
  }

  static void clear() => _cache.clear();
}
