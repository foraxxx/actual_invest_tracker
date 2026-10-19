import 'dart:math' as math;

import '../models/purchase.dart';
import 'analytics_service.dart';
import 'cash_service.dart';
import 'moex_sync_service.dart';
import 'payout_forecast_service.dart';
import 'storage_service.dart';

/// Что случилось на рынке.
class StressScenario {
  final String id;
  final String title;

  /// Подпись для показателя на главной: «если акции упадут на 20%».
  final String caption;

  /// Изменение цен акций, %.
  final double stocks;

  /// Изменение ключевой ставки, процентных пунктов.
  final double rate;

  /// Изменение курса валют к рублю, %.
  final double fx;

  const StressScenario({
    required this.id,
    required this.title,
    required this.caption,
    this.stocks = 0,
    this.rate = 0,
    this.fx = 0,
  });

  StressScenario copyWith({double? stocks, double? rate, double? fx}) => StressScenario(
        id: id,
        title: title,
        caption: caption,
        stocks: stocks ?? this.stocks,
        rate: rate ?? this.rate,
        fx: fx ?? this.fx,
      );
}

/// Группы бумаг в результате.
enum StressGroup { stocks, bonds, funds, currency, cash }

extension StressGroupTitle on StressGroup {
  String get title => switch (this) {
        StressGroup.stocks => 'Акции',
        StressGroup.bonds => 'Облигации',
        StressGroup.funds => 'Фонды',
        StressGroup.currency => 'Валюта и золото',
        StressGroup.cash => 'Свободные деньги',
      };
}

class StressImpact {
  final String ticker;
  final String name;
  final StressGroup group;
  final double value;

  /// Изменение стоимости в рублях.
  final double delta;

  /// Почему так: «дюрация 2,8 года», «по курсу валюты».
  final String reason;

  const StressImpact({
    required this.ticker,
    required this.name,
    required this.group,
    required this.value,
    required this.delta,
    required this.reason,
  });

  double get pct => value == 0 ? 0 : delta / value * 100;
}

class StressResult {
  final StressScenario scenario;
  final List<StressImpact> impacts;

  const StressResult(this.scenario, this.impacts);

  double get before => impacts.fold(0.0, (s, i) => s + i.value);
  double get delta => impacts.fold(0.0, (s, i) => s + i.delta);
  double get after => before + delta;
  double get pct => before == 0 ? 0 : delta / before * 100;

  /// Итог по группам: стоимость и изменение.
  Map<StressGroup, (double, double)> get byGroup {
    final map = <StressGroup, (double, double)>{};
    for (final i in impacts) {
      final cur = map[i.group] ?? (0.0, 0.0);
      map[i.group] = (cur.$1 + i.value, cur.$2 + i.delta);
    }
    return map;
  }

  /// Бумаги, которые потеряют больше всего, по убыванию потерь.
  List<StressImpact> get worst =>
      (impacts.where((i) => i.delta < -0.5).toList()..sort((a, b) => a.delta.compareTo(b.delta)));
}

/// «Стресс-тест»: как изменится стоимость портфеля, если упадут акции,
/// вырастет ставка или подорожает валюта. Это грубая оценка по типам бумаг,
/// а не прогноз.
class StressTestService {
  StressTestService._();

  static const scenarios = [
    StressScenario(id: 'stocks', title: 'Акции −20%', caption: 'если акции упадут на 20%', stocks: -20),
    StressScenario(id: 'rateUp', title: 'Ставка +2', caption: 'если ключевая ставка вырастет на 2 п.п.', rate: 2),
    StressScenario(
      id: 'crisis',
      title: 'Кризис',
      caption: 'акции −30%, ставка +3 п.п., валюта +20%',
      stocks: -30,
      rate: 3,
      fx: 20,
    ),
    StressScenario(id: 'rateDown', title: 'Ставка −2', caption: 'если ключевая ставка снизится на 2 п.п.', rate: -2),
  ];

  static const custom = StressScenario(id: 'custom', title: 'Свой', caption: 'свой сценарий');

  /// Фонды денежного рынка: цена растёт каждый день и от рынка почти не зависит.
  static const _moneyFunds = {
    'LQDT', 'AKMM', 'SBMM', 'TMON', 'AMNR', 'SCLI', 'MONY', 'PSMM', 'BCSD', 'CNYM', 'AMNY', 'AKCB',
  };

  /// Валютные фонды денежного рынка — по курсу.
  static const _fxMoneyFunds = {'CNYM', 'AMNY', 'AKCB'};

  /// Фонды на золото — как валюта: золото считается в долларах.
  static const _goldFunds = {'TGLD', 'AKGD', 'SBGD', 'GOLD', 'VTBG', 'GLDR'};

  /// Фонды облигаций: средняя дюрация около трёх лет.
  static const _bondFunds = {
    'SBGB', 'AKMB', 'TBRU', 'OBLG', 'SBRB', 'TOFZ', 'TPAY', 'SBCB', 'AKFB', 'TLCB', 'RCMB', 'SBRI', 'INFL',
  };

  /// Модифицированная дюрация облигации, которая торгуется около номинала:
  /// на сколько процентов упадёт цена при росте доходности на 1 п.п.
  static double bondDuration({required double yieldPct, required double years}) {
    if (years <= 0) return 0;
    final y = yieldPct / 100;
    if (y <= 0.0001) return years;
    return (1 - math.pow(1 + y, -years)) / y;
  }

  static AssetType _typeOf(String ticker) {
    final key = ticker.toUpperCase();
    for (final p in StorageService.purchases.reversed) {
      if (p.ticker.toUpperCase() == key) return p.type;
    }
    return MoexSyncService.marketSnapshot.value[key]?.isBond == true ? AssetType.bond : AssetType.stock;
  }

  static String _nameOf(String ticker) {
    final key = ticker.toUpperCase();
    for (final p in StorageService.purchases.reversed) {
      if (p.ticker.toUpperCase() == key && p.name.trim().isNotEmpty) return p.name;
    }
    final quote = MoexSyncService.marketSnapshot.value[key];
    return quote == null || quote.shortName.isEmpty ? ticker : quote.shortName;
  }

  /// Лет до погашения облигации: из котировки или графика выплат.
  static double? _yearsToMaturity(String ticker, DateTime now) {
    DateTime? mat = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()]?.matDate;
    if (mat == null) {
      for (final p in PayoutForecastService.payoutsFor(ticker)) {
        if (p.kind == 'Погашение номинала' && (mat == null || p.date.isAfter(mat))) mat = p.date;
      }
    }
    if (mat == null) return null;
    final days = mat.difference(now).inDays;
    return days <= 0 ? 0 : days / 365;
  }

  static bool _isFloater(String name) {
    final n = name.toUpperCase();
    return RegExp(r'(^|[^А-ЯA-Z])ПК(\d|$|[^А-ЯA-Z])').hasMatch(n) || n.contains('ФЛОАТ');
  }

  static String _num(double v) {
    final s = v.toStringAsFixed(1).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  static StressResult run(StressScenario s, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final snapshot = MoexSyncService.marketSnapshot.value;
    final impacts = <StressImpact>[];

    AnalyticsService.currentHoldings().forEach((ticker, h) {
      if (h.valueRub <= 0) return;
      final key = ticker.toUpperCase();
      final type = _typeOf(ticker);
      final name = _nameOf(ticker);
      final foreign = h.currency.toUpperCase() != 'RUB' && h.currency.toUpperCase() != 'SUR';
      final fx = s.fx / 100;

      StressGroup group;
      double change;
      String reason;

      switch (type) {
        case AssetType.bond:
          group = StressGroup.bonds;
          final quote = snapshot[key];
          final faceForeign = quote != null && quote.faceUnit.toUpperCase() != 'SUR' && quote.faceUnit.toUpperCase() != 'RUB';
          if (_isFloater(name)) {
            change = 0;
            reason = 'купон следует за ставкой';
          } else {
            final years = _yearsToMaturity(ticker, today) ?? 3;
            final dur = bondDuration(yieldPct: quote?.yieldPct ?? 14, years: years);
            change = (-dur * s.rate / 100).clamp(-0.6, 0.6).toDouble();
            reason = 'дюрация ${_num(dur)} ${_years(dur)}';
          }
          if (foreign || faceForeign) {
            change = (1 + change) * (1 + fx) - 1;
            reason = '$reason, номинал в валюте';
          }
        case AssetType.currency:
          group = StressGroup.currency;
          change = fx;
          reason = 'по курсу валюты';
        case AssetType.etf:
          if (_moneyFunds.contains(key)) {
            group = StressGroup.funds;
            change = _fxMoneyFunds.contains(key) ? fx : 0;
            reason = _fxMoneyFunds.contains(key) ? 'фонд денежного рынка в валюте' : 'фонд денежного рынка';
          } else if (_goldFunds.contains(key)) {
            group = StressGroup.currency;
            change = fx;
            reason = 'золото — по курсу доллара';
          } else if (_bondFunds.contains(key)) {
            group = StressGroup.funds;
            change = -3 * s.rate / 100;
            reason = 'фонд облигаций, дюрация около 3 лет';
          } else {
            group = StressGroup.funds;
            change = s.stocks / 100;
            reason = 'фонд акций';
            if (foreign) {
              change = (1 + change) * (1 + fx) - 1;
              reason = 'фонд акций в валюте';
            }
          }
        default:
          group = StressGroup.stocks;
          change = s.stocks / 100;
          reason = 'вместе с рынком акций';
          if (foreign) {
            change = (1 + change) * (1 + fx) - 1;
            reason = 'акция в валюте';
          }
      }

      impacts.add(StressImpact(
        ticker: ticker,
        name: name,
        group: group,
        value: h.valueRub,
        delta: h.valueRub * change,
        reason: reason,
      ));
    });

    final cash = CashService.summary().cash;
    if (cash > 0.5) {
      impacts.add(StressImpact(
        ticker: '',
        name: 'Свободные деньги',
        group: StressGroup.cash,
        value: cash,
        delta: 0,
        reason: 'рубли на счёте не меняются',
      ));
    }
    return StressResult(s, impacts);
  }

  static String _years(double v) {
    final whole = v.truncate();
    if (whole != v) return 'года';
    final n = whole % 100;
    if (n >= 11 && n <= 14) return 'лет';
    return switch (whole % 10) { 1 => 'год', 2 || 3 || 4 => 'года', _ => 'лет' };
  }
}
