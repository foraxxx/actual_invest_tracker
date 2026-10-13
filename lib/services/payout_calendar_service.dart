import 'currency_service.dart';
import 'payout_forecast_service.dart';
import 'storage_service.dart';

/// Одна выплата в месяце календаря: полученная или ожидаемая.
class PayoutItem {
  /// Дата, если известна. У ожидаемой выплаты без объявленной даты — null.
  final DateTime? date;
  final String ticker;
  final double rub;
  final bool expected;

  const PayoutItem({required this.ticker, required this.rub, this.date, this.expected = false});
}

/// Один месяц календаря выплат.
class PayoutMonthCell {
  final DateTime month;

  /// Уже получено (после налога, как и везде в полученных выплатах).
  final double received;

  /// Ещё ожидается по прогнозу.
  final double expected;

  /// Сколько выплат уже пришло в этом месяце.
  final int receivedCount;

  /// Каждая выплата месяца: сначала по дате, ожидаемые без даты — в конце.
  final List<PayoutItem> items;

  const PayoutMonthCell({
    required this.month,
    this.received = 0,
    this.expected = 0,
    this.receivedCount = 0,
    this.items = const [],
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
  static List<int> years({DateTime? now, bool withForecast = true}) {
    final today = now ?? DateTime.now();
    final result = <int>{today.year};
    for (final i in StorageService.incomes) {
      result.add(i.date.year);
    }
    if (withForecast) {
      final forecast = PayoutForecastService.portfolioForecastByMonth(from: today);
      final nextYear = '${today.year + 1}-';
      if (forecast.entries.any((e) => e.key.startsWith(nextYear) && e.value > 0)) {
        result.add(today.year + 1);
      }
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
          received[PayoutMonthCell.monthKey(DateTime(year, m))] ?? const [],
          PayoutMonthCell.monthKey(DateTime(year, m)) == currentKey
              ? rest
              : forecast[PayoutMonthCell.monthKey(DateTime(year, m))] ?? const {},
          today,
        ),
    ];
  }

  /// Прогноз на 12 месяцев со следующего — для окна «Прогноз выплат».
  static List<PayoutMonthCell> next12({DateTime? now}) {
    final today = now ?? DateTime.now();
    final forecast = PayoutForecastService.portfolioForecastByMonthDetailed(from: today);
    final first = DateTime(today.year, today.month + 1);
    return [
      for (int i = 0; i < 12; i++)
        _cell(
          DateTime(first.year, first.month + i),
          const [],
          forecast[PayoutMonthCell.monthKey(DateTime(first.year, first.month + i))] ?? const {},
          today,
        ),
    ];
  }

  static PayoutMonthCell _cell(
    DateTime month,
    List<PayoutItem> got,
    Map<String, double> expected,
    DateTime today,
  ) {
    final items = <PayoutItem>[
      ...got,
      for (final e in expected.entries)
        if (e.value > 0.005)
          PayoutItem(
            ticker: e.key,
            rub: e.value,
            date: _expectedDate(e.key, month, today),
            expected: true,
          ),
    ]..sort((a, b) {
        // Без даты — в конец месяца; при равной дате полученные раньше.
        final ad = a.date, bd = b.date;
        if (ad == null && bd == null) return b.rub.compareTo(a.rub);
        if (ad == null) return 1;
        if (bd == null) return -1;
        final byDate = ad.compareTo(bd);
        if (byDate != 0) return byDate;
        return (a.expected ? 1 : 0) - (b.expected ? 1 : 0);
      });
    return PayoutMonthCell(
      month: month,
      received: got.fold(0.0, (s, i) => s + i.rub),
      receivedCount: got.length,
      expected: expected.values.fold(0.0, (s, v) => s + v),
      items: items,
    );
  }

  /// Дата ожидаемой выплаты, если биржа её объявила: первая выплата бумаги в
  /// этом месяце, ещё не прошедшая. Иначе — null, месяц известен, день нет.
  static DateTime? _expectedDate(String ticker, DateTime month, DateTime today) {
    final start = DateTime(today.year, today.month, today.day);
    DateTime? best;
    for (final p in PayoutForecastService.payoutsFor(ticker)) {
      if (!p.dateKnown || p.amount <= 0) continue;
      if (p.kind != 'Купон' && p.kind != 'Дивиденд') continue;
      if (p.date.year != month.year || p.date.month != month.month) continue;
      if (p.date.isBefore(start)) continue;
      if (best == null || p.date.isBefore(best)) best = p.date;
    }
    return best;
  }

  /// Полученные выплаты по месяцам — в рублях после налога, как в «Итогах».
  static Map<String, List<PayoutItem>> _received() {
    final map = <String, List<PayoutItem>>{};
    for (final i in StorageService.incomes) {
      final key = PayoutMonthCell.monthKey(i.date);
      final rub = CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
      (map[key] ??= []).add(PayoutItem(ticker: i.ticker, rub: rub, date: i.date));
    }
    return map;
  }

  /// Название бумаги для списка: из сделок или выплат, иначе тикер.
  static String nameOf(String ticker) {
    final upper = ticker.toUpperCase();
    for (final p in StorageService.purchases.reversed) {
      if (p.ticker.toUpperCase() == upper && p.name.trim().isNotEmpty) return p.name.trim();
    }
    for (final i in StorageService.incomes) {
      if (i.ticker.toUpperCase() == upper && i.name.trim().isNotEmpty) return i.name.trim();
    }
    return ticker;
  }
}
