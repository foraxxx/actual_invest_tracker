import 'dart:math' as math;

import 'analytics_service.dart';
import 'cash_service.dart';
import 'cbr_service.dart';
import 'portfolio_history_service.dart';
import 'storage_service.dart';

/// Точка графика «Против инфляции» — всё в процентах за год.
class ReturnPoint {
  /// Последний день месяца (для текущего месяца — сегодня).
  final DateTime date;

  /// Доходность портфеля за 12 месяцев до этой даты (при истории от полугода
  /// до года — пересчитанная в годовую). null — истории меньше полугода.
  final double? portfolio;

  /// Инфляция за 12 месяцев по данным Банка России за этот месяц.
  final double? inflation;

  /// Ключевая ставка в этом месяце.
  final double? keyRate;

  const ReturnPoint({required this.date, this.portfolio, this.inflation, this.keyRate});
}

/// Итог «Против инфляции» за период.
class RealReturn {
  final DateTime from;
  final DateTime to;

  /// true — проценты пересчитаны в годовые (период не короче года),
  /// false — проценты за сам период.
  final bool annual;

  final double portfolioPct;
  final double inflationPct;

  /// Средняя ключевая ставка за период, % годовых.
  final double? keyRateAvg;

  /// Помесячные точки графика.
  final List<ReturnPoint> points;

  const RealReturn({
    required this.from,
    required this.to,
    required this.annual,
    required this.portfolioPct,
    required this.inflationPct,
    required this.keyRateAvg,
    required this.points,
  });

  /// На сколько процентных пунктов портфель обогнал инфляцию.
  double get vsInflation => portfolioPct - inflationPct;

  /// Последняя известная доходность портфеля за 12 месяцев.
  double? get portfolio12m {
    for (final p in points.reversed) {
      if (p.portfolio != null) return p.portfolio;
    }
    return null;
  }
}

/// Счёт во времени: бумаги плюс свободные деньги, и внешние движения —
/// пополнения и выводы.
class _Account {
  final List<CashMove> moves; // по возрастанию даты
  final List<MapEntry<DateTime, double>> timeline;

  _Account(this.moves, this.timeline);

  factory _Account.load() {
    final moves = [...CashService.summary().moves]..sort((a, b) => a.date.compareTo(b.date));
    final timeline = [...PortfolioHistoryService.timeline.value]..sort((a, b) => a.key.compareTo(b.key));
    return _Account(moves, timeline);
  }

  static bool external(CashMove m) =>
      m.kind == CashMoveKind.deposit || m.kind == CashMoveKind.autoDeposit || m.kind == CashMoveKind.withdrawal;

  DateTime? get start => moves.isEmpty ? null : moves.first.date;

  double _holdings(DateTime d) {
    if (timeline.isNotEmpty && !d.isBefore(timeline.first.key)) {
      double? v;
      for (final p in timeline) {
        if (p.key.isAfter(d)) break;
        v = p.value;
      }
      if (v != null) return v;
    }
    return AnalyticsService.holdingsAt(date: d).values.fold(0.0, (s, h) => s + h.valueRub);
  }

  double _cash(DateTime d) {
    double cash = 0;
    for (final m in moves) {
      if (m.date.isAfter(d)) break;
      cash += m.amountRub;
    }
    return cash < 0 ? 0 : cash;
  }

  double valueAt(DateTime d, {bool now = false}) {
    if (start == null || d.isBefore(start!)) return 0;
    if (now) return AnalyticsService.currentPortfolioValueRub() + CashService.summary().cash;
    return _holdings(d) + _cash(d);
  }

  /// Пополнения и выводы в промежутке (from, to].
  List<(DateTime, double)> flows(DateTime from, DateTime to, {bool includeFrom = false}) => [
        for (final m in moves)
          if (external(m) &&
              (includeFrom ? !m.date.isBefore(from) : m.date.isAfter(from)) &&
              !m.date.isAfter(to))
            (m.date, m.amountRub),
      ];
}

class RealReturnService {
  RealReturnService._();

  /// Доходность по методу Дитца: прибыль, делённая на средний за период
  /// капитал. Пополнение в середине периода работает только половину срока
  /// и весит вдвое меньше — поэтому крупный взнос не искажает результат.
  static double? dietz({
    required DateTime from,
    required DateTime to,
    required double startValue,
    required double endValue,
    required List<(DateTime, double)> flows,
  }) {
    final total = to.difference(from).inSeconds;
    if (total <= 0) return null;
    double sum = 0;
    double weighted = 0;
    for (final f in flows) {
      final w = to.difference(f.$1).inSeconds / total;
      sum += f.$2;
      weighted += f.$2 * w.clamp(0.0, 1.0);
    }
    final base = startValue + weighted;
    if (base < 1) return null;
    return (endValue - startValue - sum) / base;
  }

  static DateTime _monthEnd(int year, int month) => DateTime(year, month + 1, 0, 23, 59, 59);

  /// Доходность за 12 месяцев на конец каждого месяца: месячные результаты
  /// по Дитцу перемножаются — так пополнения не выглядят доходом.
  static Map<int, double> _rolling(_Account acc, DateTime now) {
    final start = acc.start;
    if (start == null) return const {};
    final ends = <DateTime>[];
    var y = start.year;
    var m = start.month;
    while (true) {
      final e = _monthEnd(y, m);
      if (!e.isBefore(now)) {
        ends.add(now);
        break;
      }
      ends.add(e);
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }

    final monthly = <double?>[];
    var prevDate = start;
    var prevValue = 0.0;
    for (int i = 0; i < ends.length; i++) {
      final d = ends[i];
      final isNow = i == ends.length - 1;
      final value = acc.valueAt(d, now: isNow);
      final r = dietz(
        from: prevDate,
        to: d,
        startValue: prevValue,
        endValue: value,
        flows: acc.flows(prevDate, d, includeFrom: i == 0),
      );
      monthly.add(r);
      prevDate = d;
      prevValue = value;
    }

    // Окно — последние 12 месяцев. Месяц, который не удалось посчитать
    // (счёт был пуст или нет цен), просто пропускается, а не обрывает всю
    // линию. Пока истории меньше года, но уже есть полгода, результат
    // пересчитывается в годовой — иначе линия появлялась бы только через год.
    final result = <int, double>{};
    for (int i = 0; i < ends.length; i++) {
      double f = 1;
      int valid = 0;
      for (int k = math.max(0, i - 11); k <= i; k++) {
        final r = monthly[k];
        // Месяц с ростом больше чем вдвое или падением больше 60% — почти
        // наверняка дыра в истории цен, а не настоящий результат.
        if (r == null || r.isNaN || r < -0.6 || r > 1.0) continue;
        f *= 1 + r;
        valid++;
      }
      if (valid < 6 || f <= 0) continue;
      final annual = valid >= 12 ? f : math.pow(f, 12 / valid).toDouble();
      result[ends[i].year * 12 + ends[i].month - 1] = (annual - 1) * 100;
    }
    return result;
  }

  /// Считает для периода главного экрана. null — если нет данных Банка России
  /// или в периоде нет своих денег.
  static RealReturn? forPeriod(PeriodFilter f, {DateTime? now}) {
    if (now != null) return _compute(f, now);
    // Главная перестраивается часто, а расчёт идёт по всей истории счёта —
    // результат запоминается, пока не изменились сделки, цены или данные
    // Банка России.
    final today = DateTime.now();
    final key = Object.hash(
      StorageService.dataVersion.value,
      CbrService.version.value,
      identityHashCode(PortfolioHistoryService.timeline.value),
      AnalyticsService.currentPortfolioValueRub().round(),
      today.year * 400 + today.month * 32 + today.day,
    );
    if (key != _memoKey) {
      _memo.clear();
      _memoKey = key;
    }
    if (_memo.containsKey(f)) return _memo[f];
    return _memo[f] = _compute(f, today);
  }

  static final Map<PeriodFilter, RealReturn?> _memo = {};
  static int? _memoKey;

  static RealReturn? _compute(PeriodFilter f, DateTime? now) {
    if (!CbrService.hasData) return null;
    final to = now ?? DateTime.now();
    final acc = _Account.load();
    final first = acc.start;
    if (first == null) return null;

    final periodStart = AnalyticsService.periodStart(f, now: to);
    final from = periodStart == null || periodStart.isBefore(first) ? first : periodStart;
    final fromStart = !from.isAfter(first);

    final r = dietz(
      from: from,
      to: to,
      startValue: fromStart ? 0 : acc.valueAt(from),
      endValue: acc.valueAt(to, now: true),
      flows: acc.flows(from, to, includeFrom: fromStart),
    );
    final infl = CbrService.inflationFactor(from, to);
    if (r == null || infl == null) return null;

    final days = to.difference(from).inDays;
    final annual = days >= 365;
    double pct(double factor) => annual ? (math.pow(factor, 365 / days) - 1) * 100 : (factor - 1) * 100;

    // График: с начала периода, но не короче года — иначе на месяце или
    // квартале не видно, куда идут линии.
    final yearAgo = DateTime(to.year - 1, to.month, 1);
    final chartFrom = from.isBefore(yearAgo) ? from : yearAgo;
    final rolling = _rolling(acc, to);
    final points = <ReturnPoint>[];
    var y = chartFrom.year;
    var m = chartFrom.month;
    while (y * 12 + m <= to.year * 12 + to.month) {
      final end = _monthEnd(y, m);
      final date = end.isAfter(to) ? to : end;
      points.add(ReturnPoint(
        date: date,
        portfolio: rolling[y * 12 + m - 1],
        inflation: CbrService.inflationIn(date),
        keyRate: CbrService.keyRateAt(date),
      ));
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }

    return RealReturn(
      from: from,
      to: to,
      annual: annual,
      portfolioPct: pct(math.max(0.0001, 1 + r)),
      inflationPct: pct(infl),
      keyRateAvg: CbrService.averageKeyRate(from, to),
      points: points,
    );
  }
}
