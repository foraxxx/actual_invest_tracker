import 'currency_service.dart';
import 'payout_forecast_service.dart';
import 'storage_service.dart';

/// Один месяц календаря выплат.
class PayoutMonthCell {
  final DateTime month;

  /// Уже получено (после налога, как и везде в полученных выплатах).
  final double received;

  /// Ещё ожидается по прогнозу.
  final double expected;

  /// Сколько выплат уже пришло в этом месяце.
  final int receivedCount;

  /// От каких бумаг деньги: полученные и ожидаемые вместе.
  final Map<String, double> byTicker;

  const PayoutMonthCell({
    required this.month,
    this.received = 0,
    this.expected = 0,
    this.receivedCount = 0,
    this.byTicker = const {},
  });

  double get total => received + expected;
  bool get hasForecast => expected > 0.005;
  bool get isEmpty => total <= 0.005;
  String get key => monthKey(month);

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

/// Данные для календаря выплат: полученное по месяцам и прогноз на будущее.
///
/// Прогноз берётся у [PayoutForecastService] — тот же, что в карточке
/// «Прогноз» на главной, поэтому числа в календаре и в карточке совпадают.
class PayoutCalendarService {
  PayoutCalendarService._();

  /// Годы для переключателя: где есть полученные выплаты, текущий и
  /// следующий — если на него уже есть прогноз.
  static List<int> years({DateTime? now}) {
    final today = now ?? DateTime.now();
    final result = <int>{today.year};
    for (final i in StorageService.incomes) {
      result.add(i.date.year);
    }
    final forecast = PayoutForecastService.portfolioForecastByMonth(from: today);
    final nextYear = '${today.year + 1}-';
    if (forecast.entries.any((e) => e.key.startsWith(nextYear) && e.value > 0)) {
      result.add(today.year + 1);
    }
    return result.toList()..sort();
  }

  /// 12 месяцев года [year]. Прошедшие — полученное. Если [withForecast], то
  /// остаток текущего месяца и будущие месяцы дополняются прогнозом.
  static List<PayoutMonthCell> year(int year, {bool withForecast = true, DateTime? now}) {
    final today = now ?? DateTime.now();
    final received = _received();
    final forecast = withForecast
        ? PayoutForecastService.portfolioForecastByMonthDetailed(from: today)
        : const <String, Map<String, double>>{};
    final rest = withForecast
        ? PayoutForecastService.restOfCurrentMonthByTicker(from: today)
        : const <String, double>{};
    final currentKey = PayoutMonthCell.monthKey(today);

    return [
      for (int m = 1; m <= 12; m++)
        _cell(
          DateTime(year, m),
          received[PayoutMonthCell.monthKey(DateTime(year, m))],
          PayoutMonthCell.monthKey(DateTime(year, m)) == currentKey
              ? rest
              : forecast[PayoutMonthCell.monthKey(DateTime(year, m))] ?? const {},
        ),
    ];
  }

  /// Прогноз на 12 месяцев со следующего — для окна «Прогноз выплат».
  static List<PayoutMonthCell> next12({DateTime? now}) {
    final today = now ?? DateTime.now();
    final forecast = PayoutForecastService.portfolioForecastByMonthDetailed(from: today);
    final totals = PayoutForecastService.portfolioForecastByMonth(from: today);
    final first = DateTime(today.year, today.month + 1);
    return [
      for (int i = 0; i < 12; i++)
        () {
          final month = DateTime(first.year, first.month + i);
          final key = PayoutMonthCell.monthKey(month);
          final byTicker = forecast[key] ?? const <String, double>{};
          // Итог месяца берём из общего прогноза: в нём поправка на копейки
          // округления, и сумма клеток совпадает с итогом окна.
          return PayoutMonthCell(
            month: month,
            expected: totals[key] ?? 0,
            byTicker: byTicker,
          );
        }(),
    ];
  }

  static PayoutMonthCell _cell(
    DateTime month,
    ({double rub, int count, Map<String, double> byTicker})? got,
    Map<String, double> expected,
  ) {
    final byTicker = <String, double>{...?got?.byTicker};
    expected.forEach((t, v) => byTicker[t] = (byTicker[t] ?? 0) + v);
    return PayoutMonthCell(
      month: month,
      received: got?.rub ?? 0,
      receivedCount: got?.count ?? 0,
      expected: expected.values.fold(0.0, (s, v) => s + v),
      byTicker: byTicker,
    );
  }

  /// Полученные выплаты по месяцам — в рублях после налога, как в «Итогах».
  static Map<String, ({double rub, int count, Map<String, double> byTicker})> _received() {
    final map = <String, ({double rub, int count, Map<String, double> byTicker})>{};
    for (final i in StorageService.incomes) {
      final key = PayoutMonthCell.monthKey(i.date);
      final rub = CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
      final prev = map[key];
      final byTicker = <String, double>{...?prev?.byTicker};
      byTicker[i.ticker] = (byTicker[i.ticker] ?? 0) + rub;
      map[key] = (rub: (prev?.rub ?? 0) + rub, count: (prev?.count ?? 0) + 1, byTicker: byTicker);
    }
    return map;
  }

  /// Короткая подпись бумаги: тикер, а у облигаций с длинным кодом — название.
  static String label(String ticker) {
    if (ticker.length <= 6) return ticker;
    for (final p in StorageService.purchases.reversed) {
      if (p.ticker.toUpperCase() == ticker.toUpperCase() && p.name.trim().isNotEmpty) {
        return p.name.trim();
      }
    }
    for (final i in StorageService.incomes) {
      if (i.ticker.toUpperCase() == ticker.toUpperCase() && i.name.trim().isNotEmpty) {
        return i.name.trim();
      }
    }
    return ticker;
  }
}
