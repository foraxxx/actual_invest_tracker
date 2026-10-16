import 'dart:math' as math;

import 'analytics_service.dart';
import 'goal_service.dart';
import 'payout_forecast_service.dart';

/// Налог с купонов и дивидендов: прогноз выплат считается до налога, а
/// пассивный доход — это то, что придёт на счёт.
const passiveTaxRate = 0.13;

/// Один месяц прогноза выплат для цели по пассивному доходу. Суммы — после
/// налога.
class PassiveMonth {
  final DateTime month;

  /// Бумага → сумма. Купоны и объявленные дивиденды.
  final Map<String, double> sure;

  /// Бумага → сумма. Дивиденды, которые компания ещё не объявила: оценка по
  /// прошлым выплатам.
  final Map<String, double> estimated;

  const PassiveMonth({required this.month, required this.sure, required this.estimated});

  double get sureTotal => sure.values.fold(0.0, (a, v) => a + v);
  double get estimatedTotal => estimated.values.fold(0.0, (a, v) => a + v);
  double get total => sureTotal + estimatedTotal;
}

/// Расчёт по цели «пассивный доход».
class PassivePlan {
  final PassiveGoal goal;
  final List<PassiveMonth> months;

  /// Стоимость портфеля сейчас.
  final double value;

  /// Сколько откладывается в месяц: из цели или подсказка.
  final double saving;

  /// Среднемесячный рост стоимости по реалистичному сценарию.
  final double rate;

  const PassivePlan({
    required this.goal,
    required this.months,
    required this.value,
    required this.saving,
    required this.rate,
  });

  double get annual => months.fold(0.0, (a, m) => a + m.total);
  double get average => months.isEmpty ? 0 : annual / months.length;

  PassiveMonth? get weakest {
    PassiveMonth? w;
    for (final m in months) {
      if (w == null || m.total < w.total) w = m;
    }
    return w;
  }

  /// Текущий доход в смысле цели: среднее или самый слабый месяц.
  double get current => goal.mode == PassiveMode.average ? average : (weakest?.total ?? 0);

  double get progress => goal.monthly <= 0 ? 0 : (current / goal.monthly).clamp(0.0, 1.0).toDouble();
  bool get reached => current >= goal.monthly - 0.5;

  /// Доходность выплат после налога, в процентах годовых.
  double get yieldPct => value <= 0 ? 0 : annual / value * 100;

  /// Сколько должно быть в портфеле, чтобы выплаты дотянули до цели при
  /// нынешнем составе. null — выплат нет, посчитать нельзя.
  double? get neededCapital {
    if (current <= 0 || value <= 0) return null;
    return value * goal.monthly / current;
  }

  double? get shortfall {
    final n = neededCapital;
    return n == null ? null : math.max(0, n - value);
  }

  /// Через сколько месяцев портфель дорастёт до [neededCapital] с
  /// взносами [saving]. null — не за 50 лет или посчитать нельзя.
  int? get reachMonths {
    final n = neededCapital;
    if (n == null) return null;
    return GoalService.monthsToReach(current: value, target: n, monthly: saving, rate: rate);
  }

  DateTime? get reachDate {
    final m = reachMonths;
    if (m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + m);
  }

  /// Какой будет доход в месяц при стоимости портфеля [capital] — для связки
  /// с целью «накопить сумму».
  double incomeAt(double capital) => value <= 0 ? 0 : current * capital / value;
}

class PassiveGoalService {
  PassiveGoalService._();

  static String? _cacheKey;
  static PassivePlan? _cache;

  static PassivePlan plan(PassiveGoal goal) {
    final value = AnalyticsService.currentPortfolioValueRub();
    final today = DateTime.now();
    final key = '${goal.toJson()}|${(value / 1000).round()}|${PayoutForecastService.version.value}|'
        '${today.year}-${today.month}-${today.day}';
    if (key == _cacheKey && _cache != null) return _cache!;
    final saving = goal.monthlySaving ?? GoalService.suggestedMonthlySaving();
    final result = PassivePlan(
      goal: goal,
      months: forecastMonths(now: today),
      value: value,
      saving: saving,
      rate: GoalService.monthlyGrowthRate(60, value),
    );
    _cacheKey = key;
    _cache = result;
    return result;
  }

  /// 12 месяцев со следующего: прогноз выплат после налога, с разделением на
  /// точно известное и оценку.
  static List<PassiveMonth> forecastMonths({DateTime? now}) {
    final today = now ?? DateTime.now();
    final detail = PayoutForecastService.portfolioForecastByMonthDetailed(from: today);
    final first = DateTime(today.year, today.month + 1);
    final result = <PassiveMonth>[];
    for (int i = 0; i < 12; i++) {
      final month = DateTime(first.year, first.month + i);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final sure = <String, double>{};
      final estimated = <String, double>{};
      for (final e in (detail[key] ?? const <String, double>{}).entries) {
        final net = e.value * (1 - passiveTaxRate);
        if (net <= 0.5) continue;
        if (_isKnown(e.key, month)) {
          sure[e.key] = net;
        } else {
          estimated[e.key] = net;
        }
      }
      result.add(PassiveMonth(month: month, sure: sure, estimated: estimated));
    }
    return result;
  }

  /// Купоны известны по графику биржи. Дивиденд известен, только если
  /// компания уже объявила выплату в этом месяце — иначе это оценка по
  /// прошлым выплатам.
  static bool _isKnown(String ticker, DateTime month) {
    final payouts = PayoutForecastService.payoutsFor(ticker);
    if (payouts.any((p) => p.kind == 'Купон')) return true;
    return payouts.any((p) =>
        p.kind == 'Дивиденд' &&
        p.dateKnown &&
        p.amount > 0 &&
        p.date.year == month.year &&
        p.date.month == month.month);
  }
}
