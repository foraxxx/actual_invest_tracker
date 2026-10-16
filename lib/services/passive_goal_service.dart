import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'analytics_service.dart';
import 'goal_service.dart';
import 'iis_service.dart';
import 'payout_forecast_service.dart';
import 'payout_picker_service.dart';

/// Налог с дивидендов: компания удерживает его сразу, на счёт приходит сумма
/// после налога. Купоны приходят целиком — налог с них брокер удерживает в
/// конце года (на ИИС не удерживает).
const dividendTaxRate = 0.13;

/// Доходность новых покупок, если рынок недоступен и своей нет.
const fallbackNewYieldPct = 14.0;

/// Один месяц прогноза выплат для цели по пассивному доходу — суммы, которые
/// придут на счёт: купоны целиком, дивиденды после налога.
class PassiveMonth {
  final DateTime month;

  /// Бумага → сумма. Купоны и объявленные дивиденды.
  final Map<String, double> sure;

  /// Бумага → сумма. Дивиденды, которые компания ещё не объявила: оценка по
  /// прошлым выплатам.
  final Map<String, double> estimated;

  /// Сколько из этого — купоны (с них в конце года удержат налог).
  final double coupons;

  const PassiveMonth({required this.month, required this.sure, required this.estimated, this.coupons = 0});

  double get sureTotal => sure.values.fold(0.0, (a, v) => a + v);
  double get estimatedTotal => estimated.values.fold(0.0, (a, v) => a + v);
  double get total => sureTotal + estimatedTotal;
}

/// Расчёт по цели «пассивный доход».
///
/// То, что портфель уже платит, остаётся как есть. Недостающий доход
/// считается под доходность новых покупок: сколько нужно докупить облигаций,
/// чтобы они добрали разницу.
class PassivePlan {
  final PassiveGoal goal;
  final List<PassiveMonth> months;

  /// Стоимость портфеля сейчас.
  final double value;

  /// Сколько откладывается в месяц: из цели или подсказка.
  final double saving;

  /// Среднемесячный рост стоимости по реалистичному сценарию.
  final double rate;

  /// Доходность новых покупок, % годовых, и откуда она.
  final double newYieldPct;
  final bool newYieldAuto;

  /// Портфель — ИИС: налог с купонов не удерживается.
  final bool iis;

  /// Сколько из стоимости портфеля лежит в бумагах, которые платят выплаты.
  final double payingValue;

  const PassivePlan({
    required this.goal,
    required this.months,
    required this.value,
    required this.saving,
    required this.rate,
    required this.newYieldPct,
    required this.newYieldAuto,
    this.iis = false,
    this.payingValue = 0,
  });

  /// Доходность выплат тех бумаг, что платят, % годовых.
  double get payingYieldPct => payingValue <= 0 ? 0 : annual / payingValue * 100;

  /// Доход в месяц, если портфель станет [capital]: нынешние выплаты плюс
  /// докупленное под доходность новых покупок.
  double incomeAt(double capital) => current + math.max(0, capital - value) * newYieldPct / 100 / 12;

  /// Вехи пути: доля цели → через сколько месяцев (null — не за 50 лет).
  List<(double, int?)> milestones() {
    final targets = [0.25, 0.5, 0.75, 1.0];
    final result = <(double, int?)>[];
    var v = value;
    var i = 0;
    for (final t in targets) {
      if (current >= goal.monthly * t) {
        result.add((t, 0));
        continue;
      }
      int? found;
      while (i <= 600) {
        if (incomeAt(v) >= goal.monthly * t - 0.5) {
          found = i;
          break;
        }
        v = v * (1 + rate) + saving;
        i++;
      }
      result.add((t, found));
    }
    return result;
  }

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

  /// Сколько месяцев из 12 уже дотягивают до цели.
  int get monthsReached => months.where((m) => m.total >= goal.monthly - 0.5).length;

  /// Налог, который брокер удержит с купонов за год. На ИИС — 0.
  double get couponTaxYear => iis ? 0 : months.fold(0.0, (a, m) => a + m.coupons) * dividendTaxRate;

  /// Доходность выплат нынешнего портфеля, % годовых.
  double get yieldPct => value <= 0 ? 0 : annual / value * 100;

  /// Сколько дохода в месяц не хватает до цели.
  double get monthlyGap => math.max(0, goal.monthly - current);

  /// Сколько докупить под доходность новых покупок, чтобы добрать разницу.
  /// Новые бумаги считаем платящими равномерно (как облигации с частым
  /// купоном), поэтому для режима «каждый месяц» добирается разница самого
  /// слабого месяца.
  double get toBuy => newYieldPct <= 0 ? 0 : monthlyGap * 12 / (newYieldPct / 100);

  /// Каким должен стать портфель.
  double get neededCapital => value + toBuy;

  int? get monthsLeft {
    final d = goal.deadline;
    if (d == null) return null;
    return GoalService.monthsUntil(d);
  }

  /// Сколько откладывать в месяц, чтобы успеть к сроку. null — срока нет.
  double? get requiredMonthly {
    final m = monthsLeft;
    if (m == null) return null;
    return GoalService.requiredMonthly(current: value, target: neededCapital, months: m, rate: rate);
  }

  /// Хватает ли того, что откладывается, чтобы успеть к сроку.
  bool get savingEnough {
    final r = requiredMonthly;
    return r == null || saving >= r - 0.5;
  }

  /// Через сколько месяцев портфель дорастёт до нужного с взносами [saving].
  int? get reachMonths =>
      reached ? 0 : GoalService.monthsToReach(current: value, target: neededCapital, monthly: saving, rate: rate);

  DateTime? get reachDate {
    final m = reachMonths;
    if (m == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + m);
  }
}

class PassiveGoalService {
  PassiveGoalService._();

  static String? _cacheKey;
  static PassivePlan? _cache;

  static PassivePlan plan(PassiveGoal goal) {
    final value = AnalyticsService.currentPortfolioValueRub();
    final today = DateTime.now();
    final market = marketYield;
    final key = '${jsonEncode(goal.toJson())}|${(value / 1000).round()}|${PayoutForecastService.version.value}|'
        '$market|${today.year}-${today.month}-${today.day}';
    if (key == _cacheKey && _cache != null) return _cache!;
    final saving = goal.monthlySaving ?? GoalService.suggestedMonthlySaving();
    final result = PassivePlan(
      goal: goal,
      months: forecastMonths(now: today),
      value: value,
      saving: saving,
      rate: GoalService.monthlyGrowthRate(60, value),
      // Доходность новых покупок всегда автоматически — по рынку.
      newYieldPct: market ?? fallbackNewYieldPct,
      newYieldAuto: true,
      iis: IisService.current != null,
      payingValue: _payingValue(),
    );
    _cacheKey = key;
    _cache = result;
    return result;
  }

  static double _payingValue() {
    double sum = 0;
    for (final e in AnalyticsService.currentHoldings().entries) {
      if (PayoutForecastService.forecastForTicker(e.key).rub > 0) sum += e.value.valueRub;
    }
    return sum;
  }

  // --- Доходность рынка облигаций ---

  /// Последняя известная купонная доходность рынка, % годовых.
  static double? get marketYield {
    final raw = GoalService.meta('marketYield');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['v'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  static DateTime? get _marketYieldAt {
    final raw = GoalService.meta('marketYield');
    if (raw == null) return null;
    try {
      return DateTime.tryParse('${(jsonDecode(raw) as Map)['at']}');
    } catch (_) {
      return null;
    }
  }

  static bool _refreshing = false;
  static DateTime? _lastAttempt;

  /// Обновляет доходность рынка, если она старше суток. Ничего не делает без
  /// сети — остаётся прошлое значение.
  static Future<void> refreshMarketYield({bool force = false}) async {
    if (_refreshing) return;
    final at = _marketYieldAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(hours: 24)) return;
    // Без сети не стучимся на каждой перерисовке — не чаще раза в полчаса.
    final last = _lastAttempt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    _lastAttempt = DateTime.now();
    _refreshing = true;
    try {
      final v = await PayoutPickerService.marketCouponYield();
      if (v != null) {
        await GoalService.setMeta('marketYield', jsonEncode({'v': v, 'at': DateTime.now().toIso8601String()}));
        GoalService.version.value++;
      }
    } catch (_) {
      // Нет связи — считаем по прошлому значению.
    } finally {
      _refreshing = false;
    }
  }

  /// 12 месяцев со следующего: суммы, которые придут на счёт, с разделением
  /// на точно известное и оценку.
  static List<PassiveMonth> forecastMonths({DateTime? now}) {
    final today = now ?? DateTime.now();
    final detail = PayoutForecastService.portfolioForecastByMonthDetailed(from: today);
    final first = DateTime(today.year, today.month + 1);
    final isBond = <String, bool>{};
    final fromHistory = <String, bool>{};
    final result = <PassiveMonth>[];
    for (int i = 0; i < 12; i++) {
      final month = DateTime(first.year, first.month + i);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final sure = <String, double>{};
      final estimated = <String, double>{};
      double coupons = 0;
      for (final e in (detail[key] ?? const <String, double>{}).entries) {
        final ticker = e.key;
        final bond = isBond[ticker] ??= PayoutForecastService.payoutsFor(ticker).any((p) => p.kind == 'Купон');
        // Прогноз по вашим прошлым выплатам уже после налога — второй раз
        // не вычитаем.
        final history = fromHistory[ticker] ??=
            PayoutForecastService.forecastForTicker(ticker).source == 'по моим выплатам';
        final amount = bond || history ? e.value : e.value * (1 - dividendTaxRate);
        if (amount <= 0.5) continue;
        if (bond) coupons += amount;
        if (bond || _dividendAnnounced(ticker, month)) {
          sure[ticker] = amount;
        } else {
          estimated[ticker] = amount;
        }
      }
      result.add(PassiveMonth(month: month, sure: sure, estimated: estimated, coupons: coupons));
    }
    return result;
  }

  static bool _dividendAnnounced(String ticker, DateTime month) => PayoutForecastService.payoutsFor(ticker).any((p) =>
      p.kind == 'Дивиденд' &&
      p.dateKnown &&
      p.amount > 0 &&
      p.date.year == month.year &&
      p.date.month == month.month);

  /// Запускает обновление доходности рынка без ожидания.
  static void refreshInBackground() => unawaited(refreshMarketYield());
}
