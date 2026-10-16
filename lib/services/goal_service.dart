import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'analytics_service.dart';
import 'cash_service.dart';
import 'portfolio_service.dart';
import 'value_forecast_service.dart';

/// Финансовая цель портфеля: накопить [amount] к концу месяца [deadline].
class FinancialGoal {
  final double amount;

  /// Срок — месяц и год; день не важен.
  final DateTime deadline;
  final String name;

  /// Сколько человек откладывает в месяц. null — не указано, тогда берётся
  /// подсказка по прошлым пополнениям (см. GoalService.suggestedMonthlySaving).
  final double? monthlySaving;

  const FinancialGoal({required this.amount, required this.deadline, this.name = '', this.monthlySaving});

  Map<String, dynamic> toJson() => {
        'a': amount,
        'y': deadline.year,
        'm': deadline.month,
        if (name.isNotEmpty) 'n': name,
        if (monthlySaving != null) 's': monthlySaving,
      };

  static FinancialGoal? fromJson(Map<String, dynamic> j) {
    final a = (j['a'] as num?)?.toDouble();
    final y = (j['y'] as num?)?.toInt();
    final m = (j['m'] as num?)?.toInt();
    if (a == null || y == null || m == null || a <= 0) return null;
    final saving = (j['s'] as num?)?.toDouble();
    return FinancialGoal(
      amount: a,
      deadline: DateTime(y, m),
      name: '${j['n'] ?? ''}',
      monthlySaving: saving == null || saving < 0 ? null : saving,
    );
  }
}

/// Как считать пассивный доход: в среднем за год (выплаты за год ÷ 12) или
/// так, чтобы даже самый слабый месяц дотягивал до цели.
enum PassiveMode { average, everyMonth }

/// Цель по пассивному доходу: получать [monthly] ₽ в месяц выплатами.
class PassiveGoal {
  final double monthly;
  final PassiveMode mode;
  final double? monthlySaving;
  final String name;

  /// Необязательный срок — месяц и год. null — считаем, когда цель будет
  /// достигнута.
  final DateTime? deadline;

  /// Доходность новых покупок, % годовых. null — автоматически по рынку
  /// облигаций.
  final double? newYieldPct;

  const PassiveGoal({
    required this.monthly,
    this.mode = PassiveMode.average,
    this.monthlySaving,
    this.name = '',
    this.deadline,
    this.newYieldPct,
  });

  Map<String, dynamic> toJson() => {
        'i': monthly,
        'md': mode.name,
        if (monthlySaving != null) 's': monthlySaving,
        if (name.isNotEmpty) 'n': name,
        if (deadline != null) 'y': deadline!.year,
        if (deadline != null) 'm': deadline!.month,
        if (newYieldPct != null) 'r': newYieldPct,
      };

  static PassiveGoal? fromJson(Map<String, dynamic> j) {
    final i = (j['i'] as num?)?.toDouble();
    if (i == null || i <= 0) return null;
    final s = (j['s'] as num?)?.toDouble();
    final y = (j['y'] as num?)?.toInt();
    final m = (j['m'] as num?)?.toInt();
    final r = (j['r'] as num?)?.toDouble();
    return PassiveGoal(
      monthly: i,
      mode: j['md'] == PassiveMode.everyMonth.name ? PassiveMode.everyMonth : PassiveMode.average,
      monthlySaving: s == null || s < 0 ? null : s,
      name: '${j['n'] ?? ''}',
      deadline: y == null || m == null ? null : DateTime(y, m),
      newYieldPct: r == null || r <= 0 ? null : r,
    );
  }
}

/// Расчёт по цели на сегодня.
class GoalPlan {
  final FinancialGoal goal;

  /// Стоимость портфеля сейчас.
  final double current;

  /// Сколько полных месяцев осталось до срока (не меньше 0).
  final int monthsLeft;

  /// Сколько будет к сроку без новых взносов — рост по реалистичному
  /// сценарию прогноза стоимости.
  final double withoutContributions;

  /// Сколько вносить в месяц, чтобы успеть точно к сроку. 0 — успеваете и так.
  final double monthly;

  /// Среднегодовой рост, заложенный в расчёт, в процентах.
  final double annualGrowthPct;

  /// Сколько человек откладывает в месяц: из цели или подсказка.
  final double saving;

  /// Путь стоимости без взносов, с нужными взносами и с тем, что человек
  /// откладывает, — для графика.
  final List<double> pathWithout;
  final List<double> pathWith;
  final List<double> pathSaving;

  /// Через сколько месяцев от сегодня цель будет достигнута, если
  /// откладывать [saving]. null — не достигается и за 50 лет.
  final int? reachMonths;

  /// Через сколько месяцев цель будет достигнута совсем без взносов — только
  /// ростом портфеля. null — не за 50 лет.
  final int? reachWithoutMonths;

  const GoalPlan({
    required this.goal,
    required this.current,
    required this.monthsLeft,
    required this.withoutContributions,
    required this.monthly,
    required this.annualGrowthPct,
    required this.saving,
    required this.pathWithout,
    required this.pathWith,
    required this.pathSaving,
    required this.reachMonths,
    this.reachWithoutMonths,
  });

  /// Примерный месяц, когда цель будет достигнута без взносов.
  DateTime? get reachWithoutDate {
    final m = reachWithoutMonths;
    if (m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + m);
  }

  /// Сколько будет к сроку, если откладывать [saving].
  double get atDeadlineWithSaving => pathSaving.isEmpty ? current : pathSaving.last;

  /// Хватает ли того, что откладывается, чтобы успеть к сроку.
  bool get savingEnough => reached || atDeadlineWithSaving >= goal.amount - 1;

  /// Сколько не хватает в месяц до нужного взноса.
  double get savingShortfall => math.max(0, monthly - saving);

  /// Месяц, когда цель будет достигнута при взносах [saving].
  DateTime? get reachDate {
    final m = reachMonths;
    if (m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + m);
  }

  double get progress => goal.amount <= 0 ? 0 : (current / goal.amount).clamp(0.0, 1.0).toDouble();
  bool get reached => current >= goal.amount;
  bool get overdue => !reached && monthsLeft <= 0;
  double get remaining => math.max(0, goal.amount - current);
}

/// Хранит цели (по одной на портфель) и считает, сколько вносить.
class GoalService {
  GoalService._();

  static const boxName = 'goals';
  static late Box<String> _box;
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static FinancialGoal? get current => goalFor(PortfolioService.activeId);

  /// Цель любого портфеля — для общего бэкапа.
  static FinancialGoal? goalFor(String portfolioId) {
    final raw = _box.get(portfolioId);
    if (raw == null) return null;
    try {
      return FinancialGoal.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(FinancialGoal goal) async {
    await _box.put(PortfolioService.activeId, jsonEncode(goal.toJson()));
    version.value++;
  }

  static Future<void> delete() async {
    await _box.delete(PortfolioService.activeId);
    version.value++;
  }

  /// Записывает или убирает цель любого портфеля — для загрузки бэкапа.
  static Future<void> saveFor(String portfolioId, FinancialGoal? goal) async {
    if (goal == null) {
      await _box.delete(portfolioId);
    } else {
      await _box.put(portfolioId, jsonEncode(goal.toJson()));
    }
    version.value++;
  }

  /// Месяцев от сегодня до конца месяца срока.
  static int monthsUntil(DateTime deadline, [DateTime? now]) {
    final today = now ?? DateTime.now();
    return math.max(0, (deadline.year - today.year) * 12 + deadline.month - today.month);
  }

  /// Сколько вносить в месяц, чтобы из [current] за [months] месяцев при
  /// месячном росте [rate] получилось [target]. Взнос — в конце месяца.
  @visibleForTesting
  static double requiredMonthly({
    required double current,
    required double target,
    required int months,
    required double rate,
  }) {
    if (months <= 0) return math.max(0, target - current);
    final growth = math.pow(1 + rate, months).toDouble();
    final gap = target - current * growth;
    if (gap <= 0) return 0;
    if (rate.abs() < 1e-9) return gap / months;
    return gap * rate / (growth - 1);
  }

  static String? _cacheKey;
  static GoalPlan? _cache;

  /// Расчёт по цели. Главная перерисовывается при каждом обновлении цен,
  /// а расчёт гоняет прогноз по месяцам — поэтому результат запоминается,
  /// пока не изменились цель, стоимость (с точностью до тысячи) и день.
  static GoalPlan plan(FinancialGoal goal, {double? currentValue}) {
    final current = currentValue ?? AnalyticsService.currentPortfolioValueRub();
    final today = DateTime.now();
    final key = '${goal.amount}|${goal.deadline}|${goal.monthlySaving}|${(current / 1000).round()}|'
        '${today.year}-${today.month}-${today.day}';
    if (key == _cacheKey && _cache != null && _cache!.goal.name == goal.name) return _cache!;
    final result = _plan(goal, current);
    _cacheKey = key;
    _cache = result;
    return result;
  }

  static GoalPlan _plan(FinancialGoal goal, double current) {
    final months = monthsUntil(goal.deadline);

    // Рост — по реалистичному сценарию прогноза на то, что уже есть в
    // портфеле: купоны, погашения, дивиденды, рост акций. Берём из него
    // среднемесячный темп и применяем к текущей стоимости.
    final rate = monthlyGrowthRate(months, current);
    final growth = math.pow(1 + rate, months).toDouble();
    final monthly = requiredMonthly(current: current, target: goal.amount, months: months, rate: rate);

    final saving = goal.monthlySaving ?? suggestedMonthlySaving();

    final without = <double>[];
    final withContrib = <double>[];
    final withSaving = <double>[];
    var a = current;
    var b = current;
    var c = current;
    for (int i = 0; i <= months; i++) {
      without.add(a);
      withContrib.add(b);
      withSaving.add(c);
      a *= 1 + rate;
      b = b * (1 + rate) + monthly;
      c = c * (1 + rate) + saving;
    }

    return GoalPlan(
      goal: goal,
      current: current,
      monthsLeft: months,
      withoutContributions: current * growth,
      monthly: monthly,
      annualGrowthPct: (math.pow(1 + rate, 12).toDouble() - 1) * 100,
      saving: saving,
      pathWithout: without,
      pathWith: withContrib,
      pathSaving: withSaving,
      reachMonths: monthsToReach(current: current, target: goal.amount, monthly: saving, rate: rate),
      reachWithoutMonths: monthsToReach(current: current, target: goal.amount, monthly: 0, rate: rate),
    );
  }

  /// Среднемесячный темп роста по реалистичному сценарию прогноза стоимости
  /// на [months] месяцев вперёд. 0 — если прогноз посчитать нельзя.
  static double monthlyGrowthRate(int months, double current) {
    if (months <= 0 || current <= 0) return 0;
    try {
      final path = ValueForecastService.realisticPath(months);
      if (path.length > 1 && path.first.value > 0 && path.last.value > 0) {
        return math.pow(path.last.value / path.first.value, 1 / (path.length - 1)).toDouble() - 1;
      }
    } catch (_) {}
    return 0;
  }

  // --- Цель по пассивному доходу ---
  // Хранится в том же боксе, ключ — id портфеля с суффиксом.

  static String _passiveKey(String portfolioId) => '$portfolioId#passive';

  /// Служебные значения в том же боксе (например, доходность рынка).
  static String? meta(String key) => _box.get('_meta#$key');
  static Future<void> setMeta(String key, String value) => _box.put('_meta#$key', value);

  static PassiveGoal? get passive => passiveFor(PortfolioService.activeId);

  static PassiveGoal? passiveFor(String portfolioId) {
    final raw = _box.get(_passiveKey(portfolioId));
    if (raw == null) return null;
    try {
      return PassiveGoal.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePassive(PassiveGoal? goal) => savePassiveFor(PortfolioService.activeId, goal);

  static Future<void> savePassiveFor(String portfolioId, PassiveGoal? goal) async {
    if (goal == null) {
      await _box.delete(_passiveKey(portfolioId));
    } else {
      await _box.put(_passiveKey(portfolioId), jsonEncode(goal.toJson()));
    }
    version.value++;
  }

  /// Через сколько месяцев из [current] получится [target], если каждый
  /// месяц добавлять [monthly] при росте [rate]. null — не за 50 лет.
  static int? monthsToReach({
    required double current,
    required double target,
    required double monthly,
    required double rate,
  }) {
    var v = current;
    for (int i = 0; i <= 600; i++) {
      if (v >= target - 1) return i;
      v = v * (1 + rate) + monthly;
    }
    return null;
  }

  /// Подсказка, сколько человек откладывает в месяц: медиана чистых
  /// пополнений (пополнения минус выводы) за последние 6 полных месяцев.
  ///
  /// Медиана, а не среднее: один крупный перевод накоплений (например, при
  /// открытии счёта) не завышает обычный ежемесячный взнос.
  static double suggestedMonthlySaving({DateTime? now}) {
    final today = now ?? DateTime.now();
    final first = DateTime(today.year, today.month - 6);
    final current = DateTime(today.year, today.month);
    final byMonth = <String, double>{};
    for (int i = 0; i < 6; i++) {
      final d = DateTime(first.year, first.month + i);
      byMonth['${d.year}-${d.month}'] = 0;
    }
    for (final m in CashService.summary().moves) {
      if (m.date.isBefore(first) || !m.date.isBefore(current)) continue;
      if (m.kind != CashMoveKind.deposit &&
          m.kind != CashMoveKind.autoDeposit &&
          m.kind != CashMoveKind.withdrawal) {
        continue;
      }
      final key = '${m.date.year}-${m.date.month}';
      byMonth[key] = (byMonth[key] ?? 0) + m.amountRub; // вывод уже со знаком минус
    }
    final value = median(byMonth.values.toList());
    return math.max(0, (value / 100).round() * 100.0);
  }

  @visibleForTesting
  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
