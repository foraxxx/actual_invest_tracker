import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'currency_service.dart';
import 'moex_service.dart';
import 'online_settings_service.dart';
import 'storage_service.dart';
import '../models/purchase.dart';

/// Загружает дневную историю MOEX и собирает реальную историческую стоимость
/// портфеля. При отсутствии сети UI продолжает использовать локальную историю
/// ручных цен и сделок из [AnalyticsService.portfolioValueTimeline].
class PortfolioHistoryService {
  PortfolioHistoryService._();

  static final ValueNotifier<List<MapEntry<DateTime, double>>> timeline =
      ValueNotifier(const []);
  static final ValueNotifier<bool> loading = ValueNotifier(false);
  static final ValueNotifier<String?> error = ValueNotifier(null);

  /// Возвращает историю с гарантированно актуальной последней точкой.
  /// Исторические значения приходят с MOEX, а точка «сейчас» должна всегда
  /// совпадать с суммой, показанной над графиком.
  static List<MapEntry<DateTime, double>> withCurrentPoint(
    List<MapEntry<DateTime, double>> source,
    double currentValue, {
    DateTime? now,
  }) {
    final currentDate = now ?? DateTime.now();
    final result = [...source]..sort((a, b) => a.key.compareTo(b.key));
    if (result.isNotEmpty && _sameDay(result.last.key, currentDate)) {
      result[result.length - 1] = MapEntry(currentDate, currentValue);
    } else {
      result.add(MapEntry(currentDate, currentValue));
    }
    return result;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Future<void> refresh() async {
    if (loading.value || StorageService.purchases.isEmpty) {
      return;
    }
    if (!OnlineSettingsService.enabled) {
      error.value = 'Онлайн-история выключена — показаны локальные данные';
      return;
    }
    loading.value = true;
    error.value = null;
    try {
      final trades = [...StorageService.purchases]
        ..sort(AnalyticsService.compareTrades);
      final from = trades.first.date;
      final tickers = trades.map((p) => p.ticker).toSet();
      final typeByTicker = <String, AssetType>{};
      for (final trade in trades) {
        typeByTicker[trade.ticker] = trade.type;
      }
      final entries = await Future.wait(tickers.map((ticker) async {
        final type = typeByTicker[ticker];
        // История MOEX для облигаций выражена в процентах от номинала, а для
        // валют нужны отдельные инструменты. До отдельной нормализации этих
        // классов используем сохранённые цены сделок/ручные цены.
        if (type != AssetType.stock && type != AssetType.etf) {
          return MapEntry(
            ticker,
            const <MapEntry<DateTime, double>>[],
          );
        }
        final points =
            await MoexService.fetchSecurityHistory(ticker, from: from);
        return MapEntry(ticker, points);
      }));
      final histories = Map<String, List<MapEntry<DateTime, double>>>.fromEntries(
        entries.where((entry) => entry.value.isNotEmpty),
      );
      if (histories.isEmpty) {
        error.value = 'История MOEX недоступна — показаны локальные данные';
        return;
      }

      final dates = histories.values
          .expand((points) => points.map((point) => point.key))
          .toSet()
          .toList()
        ..sort();
      final currencyByTicker = <String, String>{};
      for (final trade in trades) {
        currencyByTicker[trade.ticker] = trade.currency;
      }

      final result = <MapEntry<DateTime, double>>[];
      for (final date in dates) {
        double total = 0;
        for (final ticker in tickers) {
          double quantity = 0;
          for (final trade in trades) {
            if (trade.ticker == ticker && !trade.date.isAfter(date)) {
              quantity += trade.signedQuantity;
            }
          }
          if (quantity <= 1e-9) continue;
          double? price;
          for (final point in histories[ticker] ??
              const <MapEntry<DateTime, double>>[]) {
            if (point.key.isAfter(date)) break;
            price = point.value;
          }
          if (price == null) {
            for (final trade in trades) {
              if (trade.ticker == ticker && !trade.date.isAfter(date)) {
                price = trade.pricePerUnit;
              }
            }
          }
          if (price == null) continue;
          total += CurrencyService.toRub(
            quantity * price,
            currencyByTicker[ticker] ?? 'RUB',
            date: date,
          );
        }
        if (total > 0) result.add(MapEntry(date, total));
      }
      if (result.isNotEmpty) {
        result.add(MapEntry(
          DateTime.now(),
          AnalyticsService.currentPortfolioValueRub(),
        ));
        timeline.value = result;
      } else {
        error.value = 'Не удалось построить онлайн-график';
      }
    } catch (_) {
      error.value = 'Нет связи с MOEX — показаны локальные данные';
    } finally {
      loading.value = false;
    }
  }
}
