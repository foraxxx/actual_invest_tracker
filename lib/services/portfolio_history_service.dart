import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'currency_service.dart';
import 'moex_sync_service.dart';
import 'payout_forecast_service.dart';
import 'price_history_cache.dart';
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

  /// Цены облигации в прошлом — в валюте сделки за одну бумагу.
  ///
  /// Биржа даёт цену в процентах от номинала. Номинал на каждую дату — это
  /// сегодняшний номинал плюс всё, что было погашено после этой даты
  /// (у облигаций с амортизацией он уменьшается частями).
  static Future<List<MapEntry<DateTime, double>>> _bondHistory(String ticker, DateTime from) async {
    final quote = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()];
    final face = quote?.faceValue;
    if (face == null || face <= 0) return const [];
    final raw = await PriceHistoryCache.history(ticker, from: from, market: 'bonds', board: quote!.board);
    if (raw.isEmpty) return const [];

    final now = DateTime.now();
    final amortizations = [
      for (final p in PayoutForecastService.payoutsFor(ticker))
        if (p.kind == 'Погашение номинала' && !p.date.isAfter(now)) p,
    ];
    final unit = quote.faceUnit.toUpperCase();
    final faceCurrency = unit == 'SUR' ? 'RUB' : unit;
    String tradeCurrency = 'RUB';
    for (final t in StorageService.purchases) {
      if (t.ticker.toUpperCase() == ticker.toUpperCase()) tradeCurrency = t.currency;
    }

    return [
      for (final p in raw)
        () {
          var faceAt = face;
          for (final a in amortizations) {
            if (a.date.isAfter(p.key)) faceAt += a.amount;
          }
          final inFace = p.value / 100 * faceAt;
          if (faceCurrency == tradeCurrency) return MapEntry(p.key, inFace);
          final rub = CurrencyService.toRub(inFace, faceCurrency, date: p.key);
          final perTrade = tradeCurrency == 'RUB' ? 1.0 : CurrencyService.toRub(1, tradeCurrency, date: p.key);
          return MapEntry(p.key, perTrade <= 0 ? rub : rub / perTrade);
        }(),
    ];
  }

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
        if (type == AssetType.bond) {
          return MapEntry(ticker, await _bondHistory(ticker, from));
        }
        // Для валют нужны отдельные инструменты — их стоимость в прошлом
        // считается по ценам сделок и ручным ценам.
        if (type != AssetType.stock && type != AssetType.etf) {
          return MapEntry(
            ticker,
            const <MapEntry<DateTime, double>>[],
          );
        }
        final points = await PriceHistoryCache.history(ticker, from: from, market: 'shares');
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
        // Цена — закрытие дня, поэтому и сделки берём все за этот день, с
        // любым временем. Иначе бумаги, купленные днём, не попадали в
        // стоимость, хотя деньги на них уже ушли со счёта, — и на графиках
        // появлялись провалы.
        final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);
        double total = 0;
        for (final ticker in tickers) {
          double quantity = 0;
          for (final trade in trades) {
            if (trade.ticker == ticker && !trade.date.isAfter(dayEnd)) {
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
              if (trade.ticker == ticker && !trade.date.isAfter(dayEnd)) {
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
