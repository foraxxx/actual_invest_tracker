import 'dart:math' as math;

import 'analytics_service.dart';
import 'cash_service.dart';
import 'cbr_service.dart';
import 'portfolio_history_service.dart';
import 'storage_service.dart';

/// Точка графика «Против инфляции».
class ReturnPoint {
  final DateTime date;

  // --- Режим «С начала периода»: сколько набежало с первого дня, % ---

  /// Сколько заработал портфель (без влияния пополнений и выводов).
  final double? cumPortfolio;

  /// На сколько подорожали цены.
  final double? cumInflation;

  /// Сколько принёс бы вклад под ключевую ставку.
  final double? cumDeposit;

  // --- Режим «В годовых», % годовых ---

  /// Доходность портфеля за последние 12 месяцев (при истории от полугода
  /// до года — в пересчёте на год).
  final double? portfolio;

  /// Пока истории меньше полугода — сколько заработано с первой сделки, без
  /// пересчёта на год. Рисуется пунктиром: с годовыми значениями напрямую не
  /// сравнивается.
  final double? portfolioEarly;

  /// Инфляция за 12 месяцев по данным Банка России за этот месяц.
  final double? inflation;

  /// Ключевая ставка на эту дату.
  final double? keyRate;

  const ReturnPoint({
    required this.date,
    this.cumPortfolio,
    this.cumInflation,
    this.cumDeposit,
    this.portfolio,
    this.portfolioEarly,
    this.inflation,
    this.keyRate,
  });
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

  /// Точки графика: по неделям, а на длинной истории — по месяцам.
  final List<ReturnPoint> points;

  /// true — точки по неделям.
  final bool weekly;

  const RealReturn({
    required this.from,
    required this.to,
    required this.annual,
    required this.portfolioPct,
    required this.inflationPct,
    required this.keyRateAvg,
    required this.points,
    required this.weekly,
  });

  /// На сколько процентных пунктов портфель обогнал инфляцию.
  double get vsInflation => portfolioPct - inflationPct;

  /// Последняя известная годовая доходность портфеля.
  double? get portfolio12m {
    for (final p in points.reversed) {
      if (p.portfolio != null) return p.portfolio;
    }
    return null;
  }

  /// Итоги «с начала периода» на последнюю дату.
  ReturnPoint? get last => points.isEmpty ? null : points.last;
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

  /// Даты точек: по неделям, если период не длиннее полутора лет, иначе по
  /// концам месяцев. Последняя точка — всегда [to].
  static (List<DateTime>, bool) _grid(DateTime from, DateTime to) {
    final weekly = to.difference(from).inDays <= 550;
    // Точки — на конец дня: стоимость бумаг берётся по закрытию, и все
    // сделки и пополнения этого дня должны в неё уже войти.
    DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    final dates = <DateTime>[endOfDay(from)];
    if (weekly) {
      var d = endOfDay(from).add(const Duration(days: 7));
      while (d.isBefore(to)) {
        dates.add(d);
        d = endOfDay(d.add(const Duration(days: 7)));
      }
    } else {
      var y = from.year;
      var m = from.month;
      while (true) {
        final e = _monthEnd(y, m);
        if (!e.isBefore(to)) break;
        if (e.isAfter(dates.first)) dates.add(e);
        m++;
        if (m > 12) {
          m = 1;
          y++;
        }
      }
    }
    if (dates.last.isBefore(to)) {
      dates.add(to);
    } else {
      dates[dates.length - 1] = to;
    }
    return (dates, weekly);
  }

  /// Доходность портфеля на отрезке, %. Отрезок может начинаться до первой
  /// операции — тогда счёт на начало пуст.
  static double? _segment(_Account acc, DateTime a, DateTime b, DateTime first, DateTime now) {
    final fromStart = !a.isAfter(first);
    final start = fromStart ? first : a;
    return dietz(
      from: start,
      to: b,
      startValue: fromStart ? 0 : acc.valueAt(a),
      endValue: acc.valueAt(b, now: !b.isBefore(now)),
      flows: acc.flows(start, b, includeFrom: fromStart),
    );
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

  static RealReturn? _compute(PeriodFilter f, DateTime now) {
    if (!CbrService.hasData) return null;
    final to = now;
    final acc = _Account.load();
    final first = acc.start;
    if (first == null) return null;

    final periodStart = AnalyticsService.periodStart(f, now: to);
    final from = periodStart == null || periodStart.isBefore(first) ? first : periodStart;
    if (!to.isAfter(from)) return null;

    final (dates, weekly) = _grid(from, to);
    final points = <ReturnPoint>[];
    var cum = 1.0;
    for (int i = 0; i < dates.length; i++) {
      final d = dates[i];
      if (i > 0) {
        // Доходность «с начала периода» — цепочкой по отрезкам между точками:
        // так пополнения не выглядят заработком.
        final r = _segment(acc, dates[i - 1], d, first, to);
        // Неделя с падением больше 40% или ростом больше 60% — почти
        // наверняка дыра в истории цен, а не настоящий результат.
        final limit = weekly ? (-0.4, 0.6) : (-0.6, 1.0);
        if (r != null && r > limit.$1 && r < limit.$2) cum *= 1 + r;
      }

      // Годовая доходность: последние 12 месяцев, а пока истории меньше —
      // с первой сделки.
      final yearAgo = DateTime(d.year - 1, d.month, d.day);
      final windowStart = yearAgo.isAfter(first) ? yearAgo : first;
      final windowDays = d.difference(windowStart).inDays;
      double? annual;
      double? early;
      if (windowDays >= 7) {
        final r = _segment(acc, windowStart, d, first, to);
        if (r != null && r > -0.6 && r < 1.5) {
          if (windowDays >= 182) {
            annual = (windowDays >= 360 ? r : math.pow(1 + r, 365 / windowDays).toDouble() - 1) * 100;
          } else {
            early = r * 100;
          }
        }
      }

      final infl = CbrService.inflationFactor(from, d);
      final dep = CbrService.keyRateFactor(from, d);
      points.add(ReturnPoint(
        date: d,
        cumPortfolio: (cum - 1) * 100,
        cumInflation: infl == null ? null : (infl - 1) * 100,
        cumDeposit: dep == null ? null : (dep - 1) * 100,
        portfolio: annual,
        portfolioEarly: early,
        inflation: CbrService.inflationIn(d),
        keyRate: CbrService.keyRateAt(d),
      ));
    }

    final infl = CbrService.inflationFactor(from, to);
    if (infl == null) return null;
    final days = to.difference(from).inDays;
    final annualPeriod = days >= 365;
    double pct(double factor) =>
        annualPeriod ? (math.pow(math.max(0.0001, factor), 365 / days).toDouble() - 1) * 100 : (factor - 1) * 100;

    return RealReturn(
      from: from,
      to: to,
      annual: annualPeriod,
      portfolioPct: pct(cum),
      inflationPct: pct(infl),
      keyRateAvg: CbrService.averageKeyRate(from, to),
      points: points,
      weekly: weekly,
    );
  }
}
