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

  const FinancialGoal({required this.amount, required this.deadline, this.name = ''});

  Map<String, dynamic> toJson() => {
        'a': amount,
        'y': deadline.year,
        'm': deadline.month,
        if (name.isNotEmpty) 'n': name,
      };

  static FinancialGoal? fromJson(Map<String, dynamic> j) {
    final a = (j['a'] as num?)?.toDouble();
    final y = (j['y'] as num?)?.toInt();
    final m = (j['m'] as num?)?.toInt();
    if (a == null || y == null || m == null || a <= 0) return null;
    return FinancialGoal(amount: a, deadline: DateTime(y, m), name: '${j['n'] ?? ''}');
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

  /// Сколько вы в среднем вносили в месяц за последний год.
  final double averageMonthly;

  /// Путь стоимости без взносов и с нужными взносами — для графика.
  final List<double> pathWithout;
  final List<double> pathWith;

  const GoalPlan({
    required this.goal,
    required this.current,
    required this.monthsLeft,
    required this.withoutContributions,
    required this.monthly,
    required this.annualGrowthPct,
    required this.averageMonthly,
    required this.pathWithout,
    required this.pathWith,
  });

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

  static FinancialGoal? get current {
    final raw = _box.get(PortfolioService.activeId);
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
    final key = '${goal.amount}|${goal.deadline}|${(current / 1000).round()}|'
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
    double rate = 0;
    if (months > 0 && current > 0) {
      try {
        final path = ValueForecastService.realisticPath(months);
        if (path.length > 1 && path.first.value > 0 && path.last.value > 0) {
          rate = math.pow(path.last.value / path.first.value, 1 / (path.length - 1)).toDouble() - 1;
        }
      } catch (_) {
        rate = 0;
      }
    }
    final growth = math.pow(1 + rate, months).toDouble();
    final monthly = requiredMonthly(current: current, target: goal.amount, months: months, rate: rate);

    final without = <double>[];
    final withContrib = <double>[];
    var a = current;
    var b = current;
    for (int i = 0; i <= months; i++) {
      without.add(a);
      withContrib.add(b);
      a *= 1 + rate;
      b = b * (1 + rate) + monthly;
    }

    return GoalPlan(
      goal: goal,
      current: current,
      monthsLeft: months,
      withoutContributions: current * growth,
      monthly: monthly,
      annualGrowthPct: (math.pow(1 + rate, 12).toDouble() - 1) * 100,
      averageMonthly: _averageMonthlyContribution(),
      pathWithout: without,
      pathWith: withContrib,
    );
  }

  /// Средний чистый взнос в месяц за последние 12 месяцев: пополнения минус
  /// выводы.
  static double _averageMonthlyContribution() {
    final from = DateTime.now().subtract(const Duration(days: 365));
    double sum = 0;
    for (final m in CashService.summary().moves) {
      if (m.date.isBefore(from)) continue;
      if (m.kind == CashMoveKind.deposit || m.kind == CashMoveKind.autoDeposit) sum += m.amountRub;
      if (m.kind == CashMoveKind.withdrawal) sum += m.amountRub; // уже со знаком минус
    }
    return math.max(0, sum / 12);
  }
}
