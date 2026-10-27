import 'analytics_service.dart';
import 'currency_service.dart';
import 'memo.dart';
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
  ///
  /// Дальше следующего года не заглядываем: там были бы видны только купоны
  /// с уже известными датами, без дивидендов, и год выглядел бы обманчиво
  /// пустым.
  static List<int> years({DateTime? now, bool withForecast = true}) {
    final today = now ?? DateTime.now();
    final result = <int>{today.year};
    for (final i in StorageService.incomes) {
      if (i.date.year <= today.year) result.add(i.date.year);
    }
    if (withForecast) {
      final next = year(today.year + 1, now: today);
      if (next.any((c) => !c.isEmpty)) result.add(today.year + 1);
    }
    return result.toList()..sort();
  }

  /// 12 месяцев года [year]. Прошедшие — полученное. Если [withForecast], то
  /// остаток текущего месяца и будущие месяцы дополняются прогнозом.
  static List<PayoutMonthCell> year(int year, {bool withForecast = true, DateTime? now}) {
    if (now == null) {
      return Memo.get('payoutYear:$year:$withForecast', () => _year(year, withForecast, null));
    }
    return _year(year, withForecast, now);
  }

  static List<PayoutMonthCell> _year(int year, bool withForecast, DateTime? now) {
    final today = now ?? DateTime.now();
    final received = _received();
    final forecast = withForecast
        ? PayoutForecastService.portfolioForecastByMonthDetailed(from: today)
        : const <String, Map<String, double>>{};
    final rest = withForecast
        ? PayoutForecastService.restOfCurrentMonthByTicker(from: today)
        : const <String, double>{};
    final currentKey = PayoutMonthCell.monthKey(today);
    // Прогноз считается на 12 месяцев со следующего. Месяцы дальше него
    // заполняем выплатами, которые биржа уже поставила в график, — иначе,
    // например, декабрьский купон следующего года пропадал бы, хотя его дата
    // и сумма известны.
    final horizonEnd = DateTime(today.year, today.month + 13);

    Map<String, double> expectedFor(DateTime month) {
      final key = PayoutMonthCell.monthKey(month);
      if (!withForecast) return const {};
      if (key == currentKey) return rest;
      if (!month.isBefore(horizonEnd)) return _scheduled(month);
      return forecast[key] ?? const {};
    }

    return [
      for (int m = 1; m <= 12; m++)
        _cell(
          DateTime(year, m),
          received[PayoutMonthCell.monthKey(DateTime(year, m))] ?? const [],
          expectedFor(DateTime(year, m)),
          today,
        ),
    ];
  }

  /// Выплаты месяца по графику биржи: известные даты × нынешнее количество.
  /// Если размер будущего купона ещё не объявлен (флоатер), берём последний
  /// известный купон этой бумаги — так же считает прогноз стоимости.
  static Map<String, double> _scheduled(DateTime month) {
    final result = <String, double>{};
    for (final entry in AnalyticsService.currentHoldings().entries) {
      final qty = entry.value.qty;
      if (qty <= 0) continue;
      final payouts = PayoutForecastService.payoutsFor(entry.key)
          .where((p) => p.kind == 'Купон' || p.kind == 'Дивиденд')
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      double lastCoupon = 0;
      for (final p in payouts) {
        if (p.kind == 'Купон' && p.amount > 0 && p.date.isBefore(month)) lastCoupon = p.amount;
        if (!p.dateKnown || p.date.year != month.year || p.date.month != month.month) continue;
        final perUnit = p.amount > 0 ? p.amount : (p.kind == 'Купон' ? lastCoupon : 0.0);
        if (perUnit <= 0) continue;
        // Мосбиржа пишет рубль как SUR — переводим в понятный приложению код.
        final raw = p.currency.toUpperCase();
        final currency = (raw == 'SUR' || raw.isEmpty) ? 'RUB' : raw;
        final rub = CurrencyService.toRub(perUnit * qty * PayoutForecastService.netFactor, currency);
        result[entry.key] = (result[entry.key] ?? 0) + rub;
      }
    }
    return result;
  }

  /// Прогноз на 12 месяцев со следующего — для окна «Прогноз выплат».
  static List<PayoutMonthCell> next12({DateTime? now}) {
    if (now == null) return Memo.get('payoutNext12', () => _next12(null));
    return _next12(now);
  }

  static List<PayoutMonthCell> _next12(DateTime? now) {
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
  static Map<String, List<PayoutItem>> _received() => Memo.get('payoutsReceived', _receivedNow);

  static Map<String, List<PayoutItem>> _receivedNow() {
    final map = <String, List<PayoutItem>>{};
    for (final i in StorageService.incomes) {
      final key = PayoutMonthCell.monthKey(i.date);
      final rub = CurrencyService.toRub(i.amountNet, i.currency, date: i.date);
      (map[key] ??= []).add(PayoutItem(ticker: i.ticker, rub: rub, date: i.date));
    }
    return map;
  }

  /// Название бумаги для списка: из сделок или выплат, иначе тикер.
  static String nameOf(String ticker) => _names()[ticker.toUpperCase()] ?? ticker;

  /// Названия всех бумаг одним словарём: раньше на каждую строку списка
  /// перебирались все сделки и выплаты.
  static Map<String, String> _names() => Memo.get('payoutNames', () {
        final map = <String, String>{};
        // Сначала выплаты, потом сделки по порядку: последняя сделка с
        // непустым названием перезапишет остальное — как и раньше.
        for (final i in StorageService.incomes) {
          final upper = i.ticker.toUpperCase();
          if (i.name.trim().isNotEmpty) map.putIfAbsent(upper, () => i.name.trim());
        }
        for (final p in StorageService.purchases) {
          if (p.name.trim().isNotEmpty) map[p.ticker.toUpperCase()] = p.name.trim();
        }
        return map;
      });
}
