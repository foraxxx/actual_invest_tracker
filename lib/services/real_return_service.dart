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

  /// Доходность портфеля за период в пересчёте на год — для подписи
  /// «≈ +7.6% годовых» рядом с результатом за неполный год.
  final double? portfolioPerYear;

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
    this.portfolioPerYear,
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

  static bool isExternal(CashMove m) =>
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
          if (isExternal(m) &&
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
    if (first == null || !to.isAfter(first)) return null;

    // Одна шкала на всю историю: недели с первой операции до сегодня. По ней
    // цепочкой считается «индекс» портфеля — сколько стал бы стоить рубль,
    // вложенный в первый день, без влияния пополнений и выводов. Из этого
    // одного индекса берутся и «с начала периода», и «в годовых», и итог под
    // графиком — поэтому цифры между собой сходятся.
    DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    final grid = <DateTime>[endOfDay(first)];
    var g = endOfDay(first).add(const Duration(days: 7));
    while (g.isBefore(to)) {
      grid.add(g);
      g = endOfDay(g.add(const Duration(days: 7)));
    }
    if (grid.last.isBefore(to)) {
      grid.add(to);
    } else {
      grid[grid.length - 1] = to;
    }

    final idx = <double>[1.0];
    for (int i = 1; i < grid.length; i++) {
      final r = _segment(acc, grid[i - 1], grid[i], first, to);
      // Неделя с падением больше 40% или ростом больше 60% — почти
      // наверняка дыра в истории цен, а не настоящий результат.
      final ok = r != null && r > -0.4 && r < 0.6;
      idx.add(idx.last * (ok ? 1 + r : 1));
    }

    // Начало периода — ближайшая неделя шкалы.
    final periodStart = AnalyticsService.periodStart(f, now: to);
    var p = 0;
    if (periodStart != null) {
      while (p < grid.length - 1 && grid[p].isBefore(periodStart)) {
        p++;
      }
    }
    final from = p == 0 ? first : grid[p];
    if (p >= grid.length - 1) return null;

    // На длинной истории показываем по одной точке на месяц.
    final weekly = to.difference(from).inDays <= 550;
    final shown = <int>[];
    for (int k = p; k < grid.length; k++) {
      final isLast = k == grid.length - 1;
      if (weekly || isLast || grid[k + 1].month != grid[k].month) shown.add(k);
    }

    double annualAt(int k) {
      final days = grid[k].difference(grid[0]).inDays;
      if (days >= 365) {
        final yearAgo = DateTime(grid[k].year - 1, grid[k].month, grid[k].day);
        var j = 0;
        while (j < k && grid[j + 1].isBefore(yearAgo)) {
          j++;
        }
        final span = grid[k].difference(grid[j]).inDays;
        final r = idx[k] / idx[j];
        return (span >= 360 && span <= 372 ? r - 1 : math.pow(r, 365 / span).toDouble() - 1) * 100;
      }
      return (math.pow(idx[k] / idx[0], 365 / days).toDouble() - 1) * 100;
    }

    final points = <ReturnPoint>[];
    var bridged = false;
    for (int n = 0; n < shown.length; n++) {
      final k = shown[n];
      final d = grid[k];
      final sinceFirst = d.difference(grid[0]).inDays;
      double? annual;
      double? early;
      if (sinceFirst >= 182) {
        annual = annualAt(k);
        // Пунктир доводим до первой точки сплошной линии — без разрыва.
        if (!bridged && n > 0 && points.last.portfolioEarly != null) early = annual;
        bridged = true;
      } else if (sinceFirst >= 7) {
        early = (idx[k] / idx[0] - 1) * 100;
      }
      final infl = CbrService.inflationFactor(from, d);
      final dep = CbrService.keyRateFactor(from, d);
      points.add(ReturnPoint(
        date: d,
        cumPortfolio: (idx[k] / idx[p] - 1) * 100,
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
    final growth = idx.last / idx[p];
    double pct(double factor) =>
        annualPeriod ? (math.pow(math.max(0.0001, factor), 365 / days).toDouble() - 1) * 100 : (factor - 1) * 100;

    return RealReturn(
      from: from,
      to: to,
      annual: annualPeriod,
      portfolioPct: pct(growth),
      inflationPct: pct(infl),
      portfolioPerYear: days >= 30 ? (math.pow(math.max(0.0001, growth), 365 / days).toDouble() - 1) * 100 : null,
      keyRateAvg: CbrService.averageKeyRate(from, to),
      points: points,
      weekly: weekly,
    );
  }
}
