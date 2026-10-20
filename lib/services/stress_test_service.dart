import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/purchase.dart';
import 'analytics_service.dart';
import 'appearance_service.dart';
import 'beta_service.dart';
import 'cash_service.dart';
import 'memo.dart';
import 'moex_sync_service.dart';
import 'payout_forecast_service.dart';
import 'sector_service.dart';
import 'storage_service.dart';

/// Что случилось на рынке: три фактора, из которых складывается изменение
/// каждой бумаги.
class StressScenario {
  final String id;
  final String title;

  /// Описание в списке: «рынок падает, ставка и курс прежние».
  final String caption;

  /// Движение рынка акций, % — без учёта ставки: её влияние на акции
  /// добавляется отдельно.
  final double market;

  /// Изменение ключевой ставки, процентных пунктов.
  final double rate;

  /// Изменение рубля, %: −20 — рубль подешевел на 20%, доллар и юань
  /// подорожали на 25%.
  final double ruble;

  const StressScenario({
    required this.id,
    required this.title,
    required this.caption,
    this.market = 0,
    this.rate = 0,
    this.ruble = 0,
  });

  StressScenario copyWith({double? market, double? rate, double? ruble}) => StressScenario(
        id: id,
        title: title,
        caption: caption,
        market: market ?? this.market,
        rate: rate ?? this.rate,
        ruble: ruble ?? this.ruble,
      );

  bool sameAs(StressScenario o) => market == o.market && rate == o.rate && ruble == o.ruble;

  /// Насколько подорожает валюта, доля: рубль −20% → доллар +25%.
  double get fx => ruble <= -99 ? 0 : 1 / (1 + ruble / 100) - 1;
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

/// Метка у бумаги: «рынок −28%», «до 2041 года».
class StressTag {
  final String text;

  /// −1 — потеря, 1 — рост, 0 — пояснение без знака.
  final int sign;

  const StressTag(this.text, this.sign);
}

class StressImpact {
  final String ticker;
  final String name;
  final StressGroup group;
  final double value;

  /// Части изменения в рублях: от рынка, от ставки (с кредитными спредами)
  /// и от курса.
  final double market;
  final double rate;
  final double fx;

  final List<StressTag> tags;

  const StressImpact({
    required this.ticker,
    required this.name,
    required this.group,
    required this.value,
    required this.market,
    required this.rate,
    required this.fx,
    required this.tags,
  });

  double get delta => market + rate + fx;
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

  double get fromMarket => impacts.fold(0.0, (s, i) => s + i.market);
  double get fromRate => impacts.fold(0.0, (s, i) => s + i.rate);
  double get fromFx => impacts.fold(0.0, (s, i) => s + i.fx);

  /// Итог по группам: стоимость и изменение.
  Map<StressGroup, (double, double)> get byGroup {
    final map = <StressGroup, (double, double)>{};
    for (final i in impacts) {
      final cur = map[i.group] ?? (0.0, 0.0);
      map[i.group] = (cur.$1 + i.value, cur.$2 + i.delta);
    }
    return map;
  }
}

/// Как отрасль реагирует на три фактора.
class _Sensitivity {
  /// Бета — движение вместе с рынком.
  final double beta;

  /// Изменение цены, % на каждый пункт ставки. Складывается из двух вещей:
  /// дорогие деньги удешевляют все акции, но у компаний с большими деньгами
  /// на счетах (Сургутнефтегаз, Мосбиржа, НМТП) растёт доход от процентов —
  /// у них итог может быть в плюс.
  final double rate;

  /// Доля роста валюты, которая переходит в цену: 0.4 — доллар +10%,
  /// акция +4%.
  final double fx;

  const _Sensitivity(this.beta, this.rate, this.fx);
}

/// «Стресс-тест»: как изменится стоимость портфеля при резких событиях.
///
/// Каждая бумага складывает три реакции:
/// * на рынок — по бете: своей, посчитанной по истории цен, или средней для
///   отрасли;
/// * на ставку — облигации по дюрации, акции в среднем −4% на пункт (сильнее
///   застройщики и IT, слабее экспортёры), в кризис корпоративные облигации
///   теряют ещё и на расширении спредов;
/// * на курс — валюта и золото целиком, экспортёры частично (префы
///   Сургутнефтегаза — почти целиком из-за валютных депозитов компании),
///   импортёры в обратную сторону.
///
/// Это оценка чувствительности, а не прогноз.
class StressTestService {
  StressTestService._();

  static final ValueNotifier<int> version = ValueNotifier(0);

  static const scenarios = [
    StressScenario(id: 'stocks', title: 'Акции −20%', caption: 'рынок падает, ставка и курс прежние', market: -20),
    StressScenario(id: 'rateUp', title: 'Ставка +2', caption: 'облигации и акции дешевеют', rate: 2),
    StressScenario(id: 'ruble', title: 'Рубль −20%', caption: 'доллар и юань дорожают на 25%', ruble: -20),
    StressScenario(
      id: 'crisis',
      title: 'Кризис',
      caption: 'рынок −25%, ставка +3 п.п., рубль −20%',
      market: -25,
      rate: 3,
      ruble: -20,
    ),
    StressScenario(id: 'rateDown', title: 'Ставка −2', caption: 'облигации и акции дорожают', rate: -2),
  ];

  /// Свой сценарий: ползунки запоминаются между запусками.
  static StressScenario get custom {
    const base = StressScenario(id: 'custom', title: 'Свой', caption: 'свой сценарий');
    final raw = AppearanceService.ui('stressCustom');
    if (raw == null) return base.copyWith(market: -30, rate: 3, ruble: -10);
    try {
      final m = jsonDecode(raw) as Map;
      return base.copyWith(
        market: (m['m'] as num).toDouble(),
        rate: (m['r'] as num).toDouble(),
        ruble: (m['f'] as num).toDouble(),
      );
    } catch (_) {
      return base;
    }
  }

  static Future<void> saveCustom(StressScenario s) async {
    await AppearanceService.setUi('stressCustom', jsonEncode({'m': s.market, 'r': s.rate, 'f': s.ruble}));
  }

  /// Примерное изменение индекса МосБиржи в сценарии: рынок, средняя
  /// реакция акций на ставку и немного курса — в индексе много экспортёров.
  static double indexChange(StressScenario s) =>
      (s.market / 100 + _index.rate * s.rate / 100 + _index.fx * s.fx) * 100;

  static const _index = _Sensitivity(1, -4, 0.15);

  static const _sectors = <String, _Sensitivity>{
    'oil': _Sensitivity(0.9, -2.5, 0.35),
    'metals': _Sensitivity(1.0, -3, 0.4),
    'chem': _Sensitivity(0.9, -3, 0.4),
    'finance': _Sensitivity(1.15, -4.5, 0.03),
    'it': _Sensitivity(1.3, -6, 0),
    'retail': _Sensitivity(0.9, -4, -0.15),
    'telecom': _Sensitivity(0.8, -5, -0.05),
    'power': _Sensitivity(0.9, -4, -0.03),
    'transport': _Sensitivity(1.1, -4.5, -0.2),
    'realty': _Sensitivity(1.3, -7, 0),
    'export': _Sensitivity(1.0, -3, 0.5),
  };

  static const _default = _Sensitivity(1.0, -4, 0.1);

  /// Отдельные бумаги: бета по умолчанию, реакция на ставку и доля роста
  /// валюты, которая переходит в цену. Отрасль даёт только среднее, а внутри
  /// неё компании устроены по-разному: у НМТП тарифы порта в долларах, у
  /// Совкомфлота фрахт в долларах, а М.Видео и Fix Price, наоборот, закупают
  /// товар за валюту.
  static const _tickers = <String, _Sensitivity>{
    // Нефть и газ: выручка в долларах, налоги и часть затрат в рублях.
    'GAZP': _Sensitivity(0.9, -3, 0.35),
    'LKOH': _Sensitivity(0.9, -1.5, 0.5),
    'ROSN': _Sensitivity(0.95, -3, 0.45),
    'NVTK': _Sensitivity(0.95, -3, 0.5),
    'TATN': _Sensitivity(0.9, -2.5, 0.45),
    'TATNP': _Sensitivity(0.85, -2.5, 0.45),
    'SIBN': _Sensitivity(0.85, -2.5, 0.35),
    'BANE': _Sensitivity(0.8, -2.5, 0.4),
    'BANEP': _Sensitivity(0.8, -2.5, 0.4),
    // Дивиденд по префам почти целиком зависит от переоценки валютных
    // депозитов компании.
    'SNGSP': _Sensitivity(0.6, 1, 0.9),
    'SNGS': _Sensitivity(0.8, 0.5, 0.3),
    // Транснефть: тарифы рублёвые, валюты почти нет.
    'TRNFP': _Sensitivity(0.8, 0, 0.1),
    // Металлы, золото, уголь, удобрения — экспортёры.
    'GMKN': _Sensitivity(1.0, -3.5, 0.6),
    'NLMK': _Sensitivity(1.0, -3, 0.5),
    'CHMF': _Sensitivity(1.0, -3, 0.45),
    'MAGN': _Sensitivity(1.0, -3, 0.35),
    'ALRS': _Sensitivity(0.9, -3, 0.6),
    'PLZL': _Sensitivity(0.8, -2.5, 0.75),
    'UGLD': _Sensitivity(1.0, -3.5, 0.6),
    'SELG': _Sensitivity(1.1, -4, 0.6),
    'RUAL': _Sensitivity(1.0, -4, 0.6),
    'VSMO': _Sensitivity(0.8, -3, 0.6),
    'RASP': _Sensitivity(1.1, -3.5, 0.6),
    'MTLR': _Sensitivity(1.3, -5, 0.5),
    'MTLRP': _Sensitivity(1.2, -5, 0.5),
    'ENPG': _Sensitivity(1.0, -4, 0.5),
    'TRMK': _Sensitivity(0.9, -4, 0.3),
    'PHOR': _Sensitivity(0.7, -2.5, 0.6),
    'AKRN': _Sensitivity(0.7, -2.5, 0.6),
    'NKNC': _Sensitivity(0.9, -3, 0.35),
    // Порты, морские перевозки, лес — валютная выручка.
    'NMTP': _Sensitivity(0.9, 0.7, 0.6),
    'FESH': _Sensitivity(1.2, -4, 0.5),
    'FLOT': _Sensitivity(1.0, -1, 0.8),
    'SGZH': _Sensitivity(1.3, -8, 0.4),
    'AQUA': _Sensitivity(0.8, -3.5, 0.25),
    // Валютные затраты: самолёты и топливо, импорт товаров и машин.
    'AFLT': _Sensitivity(1.2, -5, -0.35),
    'MVID': _Sensitivity(1.3, -8, -0.4),
    'FIXP': _Sensitivity(0.9, -4, -0.3),
    'SVAV': _Sensitivity(1.1, -5, -0.3),
    'KMAZ': _Sensitivity(1.1, -5, -0.15),
    'OZON': _Sensitivity(1.2, -5, -0.1),
    'MGNT': _Sensitivity(0.8, -4, -0.1),
    'X5': _Sensitivity(0.8, -4, -0.1),
    'LENT': _Sensitivity(0.8, -4, -0.1),
    'MTSS': _Sensitivity(0.8, -6, -0.1),
    'RTKM': _Sensitivity(0.8, -5, -0.1),
    // Банки и биржа: рублёвый бизнес; биржа выигрывает от высокой ставки.
    'SBER': _Sensitivity(1.1, -4.5, 0.05),
    'SBERP': _Sensitivity(1.1, -4.5, 0.05),
    'VTBR': _Sensitivity(1.3, -6, 0.03),
    'T': _Sensitivity(1.3, -5, 0),
    'MOEX': _Sensitivity(0.9, 1.3, 0.05),
    'CBOM': _Sensitivity(1.1, -5, 0.03),
    'BSPB': _Sensitivity(1.0, -3, 0.05),
    'SFIN': _Sensitivity(1.2, -6, 0),
    'AFKS': _Sensitivity(1.4, -8, 0),
    // IT и застройщики: дорогие деньги бьют сильнее всего.
    'YDEX': _Sensitivity(1.2, -5, 0.05),
    'HEAD': _Sensitivity(1.2, -2, 0),
    'POSI': _Sensitivity(1.4, -7, 0),
    'ASTR': _Sensitivity(1.4, -7, 0),
    'VKCO': _Sensitivity(1.5, -9, 0),
    'DIAS': _Sensitivity(1.3, -6, 0),
    'SOFL': _Sensitivity(1.4, -7, 0),
    'PIKK': _Sensitivity(1.3, -8, 0),
    'SMLT': _Sensitivity(1.5, -10, 0),
    'LSRG': _Sensitivity(1.1, -6, 0),
    'ETLN': _Sensitivity(1.3, -8, 0),
    // Электроэнергетика: рублёвые тарифы.
    'IRAO': _Sensitivity(0.8, 0.3, 0.1),
    'HYDR': _Sensitivity(0.8, -4, 0),
    'FEES': _Sensitivity(0.9, -6, -0.05),
    'UPRO': _Sensitivity(0.8, -3, -0.05),
    'MSNG': _Sensitivity(0.8, -3, -0.05),
    'OGKB': _Sensitivity(0.9, -4, -0.05),
  };

  static String _sectorKey(String sector) {
    final s = sector.toLowerCase();
    if (s.contains('нефт') || s.contains('газ')) return 'oil';
    if (s.contains('металл') || s.contains('добыч') || s.contains('горно')) return 'metals';
    if (s.contains('хими') || s.contains('удобр')) return 'chem';
    if (s.contains('финанс') || s.contains('банк')) return 'finance';
    if (s.contains('it') || s.contains('информ') || s.contains('технолог')) return 'it';
    if (s.contains('ритейл') || s.contains('потреб') || s.contains('торгов')) return 'retail';
    if (s.contains('телеком') || s.contains('связ')) return 'telecom';
    if (s.contains('электро') || s.contains('энерг')) return 'power';
    if (s.contains('порт') && !s.contains('транспорт')) return 'export';
    if (s.contains('транспорт')) return 'transport';
    if (s.contains('строит') || s.contains('недвиж') || s.contains('девелоп')) return 'realty';
    return '';
  }

  static _Sensitivity _stockSensitivity(String ticker) {
    final key = ticker.toUpperCase();
    final base = _tickers[key] ?? _sectors[_sectorKey(SectorService.sectorFor(ticker))] ?? _default;
    final hist = BetaService.betaOf(key);
    if (hist == null) return base;
    // Бета по истории немного подтягивается к средней для отрасли: на двух
    // годах данных одна новость легко её искажает.
    final beta = (hist * 0.67 + base.beta * 0.33).clamp(0.2, 2.0).toDouble();
    return _Sensitivity(beta, base.rate, base.fx);
  }

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

  static DateTime? _maturity(String ticker) {
    DateTime? mat = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()]?.matDate;
    if (mat == null) {
      for (final p in PayoutForecastService.payoutsFor(ticker)) {
        if (p.kind == 'Погашение номинала' && (mat == null || p.date.isAfter(mat))) mat = p.date;
      }
    }
    return mat;
  }

  static bool _isFloater(String name) {
    final n = name.toUpperCase();
    return RegExp(r'(^|[^А-ЯA-Z])ПК(\d|$|[^А-ЯA-Z])').hasMatch(n) || n.contains('ФЛОАТ');
  }

  static bool _isOfz(String ticker, String name) =>
      name.toUpperCase().contains('ОФЗ') || ticker.toUpperCase().startsWith('SU');

  static String _pctText(double fraction) {
    final v = fraction * 100;
    final rounded = v.abs() < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
    final clean = rounded.endsWith('.0') ? rounded.substring(0, rounded.length - 2) : rounded;
    return '${v >= 0 ? '+' : '−'}${clean.replaceAll('-', '')}%';
  }

  /// Метка «рынок −28%», если часть заметна.
  static void _tag(List<StressTag> tags, String label, double fraction) {
    if (fraction.abs() < 0.0005) return;
    tags.add(StressTag('$label ${_pctText(fraction)}', fraction < 0 ? -1 : 1));
  }

  /// Изменение кредитных спредов, п.п.: при падении рынка корпоративные
  /// облигации требуют большей доходности сверх ОФЗ.
  static double _spread(StressScenario s) => (-s.market * 0.04).clamp(-0.5, 2.0).toDouble();

  /// Итог сценария. Запоминается, пока не изменились позиции, цены или
  /// беты: на главной он нужен при каждой перерисовке.
  static StressResult run(StressScenario s, {DateTime? now}) {
    if (now != null) return _run(s, now);
    return Memo.get('stress:${s.market}:${s.rate}:${s.ruble}', () => _run(s, null));
  }

  static StressResult _run(StressScenario s, DateTime? now) {
    final today = now ?? DateTime.now();
    final snapshot = MoexSyncService.marketSnapshot.value;
    final impacts = <StressImpact>[];
    final m = s.market / 100;
    final fx = s.fx;
    final spread = _spread(s);

    AnalyticsService.currentHoldings().forEach((ticker, h) {
      if (h.valueRub <= 0) return;
      final key = ticker.toUpperCase();
      final type = _typeOf(ticker);
      final name = _nameOf(ticker);
      final cur = h.currency.toUpperCase();
      final foreign = cur != 'RUB' && cur != 'SUR';
      final tags = <StressTag>[];

      StressGroup group;
      double market = 0; // доли, в валюте бумаги
      double rate = 0;
      var fxShare = foreign ? 1.0 : 0.0; // какая доля роста валюты переходит в цену

      switch (type) {
        case AssetType.bond:
          group = StressGroup.bonds;
          final quote = snapshot[key];
          final faceForeign = quote != null && quote.faceUnit.toUpperCase() != 'SUR' && quote.faceUnit.toUpperCase() != 'RUB';
          final mat = _maturity(ticker);
          final years = mat == null ? 3.0 : math.max(0.0, mat.difference(today).inDays / 365);
          final ofz = _isOfz(ticker, name);
          if (foreign || faceForeign) {
            // Замещающие облигации: доходность в долларах от рублёвой ставки
            // не зависит, остаются курс и спред.
            final dur = bondDuration(yieldPct: quote?.yieldPct ?? 7, years: years);
            rate = (-dur * spread / 100).clamp(-0.6, 0.6).toDouble();
            fxShare = 1;
            _tag(tags, 'спред', rate);
          } else if (_isFloater(name)) {
            // Купон флоатера следует за ставкой, цена от неё почти не зависит.
            rate = ofz ? 0 : (-math.min(years, 5) * spread / 100).clamp(-0.3, 0.3).toDouble();
            _tag(tags, 'спред', rate);
            tags.add(const StressTag('флоатер', 0));
          } else {
            final dur = bondDuration(yieldPct: quote?.yieldPct ?? 14, years: years);
            final r = (-dur * s.rate / 100).clamp(-0.6, 0.6).toDouble();
            final sp = ofz ? 0.0 : (-dur * spread / 100).clamp(-0.3, 0.3).toDouble();
            rate = r + sp;
            _tag(tags, 'ставка', r);
            _tag(tags, 'спред', sp);
          }
          if (mat != null) tags.add(StressTag('до ${mat.year} года', 0));
        case AssetType.currency:
          group = StressGroup.currency;
          fxShare = 1;
        case AssetType.etf:
          if (_moneyFunds.contains(key)) {
            group = StressGroup.funds;
            fxShare = _fxMoneyFunds.contains(key) ? 1.0 : 0.0;
            tags.add(const StressTag('денежный рынок', 0));
          } else if (_goldFunds.contains(key)) {
            group = StressGroup.currency;
            fxShare = 1;
            tags.add(const StressTag('золото', 0));
          } else if (_bondFunds.contains(key)) {
            group = StressGroup.funds;
            rate = (-3 * s.rate / 100).clamp(-0.4, 0.4).toDouble();
            _tag(tags, 'ставка', rate);
          } else {
            group = StressGroup.funds;
            final hist = BetaService.betaOf(key);
            final beta = hist == null ? 1.0 : (hist * 0.67 + 0.33).clamp(0.2, 2.0).toDouble();
            market = beta * m;
            rate = _index.rate * s.rate / 100;
            if (!foreign) fxShare = _index.fx;
            _tag(tags, 'рынок', market);
            _tag(tags, 'ставка', rate);
          }
        default:
          group = StressGroup.stocks;
          final sens = _stockSensitivity(ticker);
          market = sens.beta * m;
          rate = sens.rate * s.rate / 100;
          if (!foreign) fxShare = sens.fx;
          _tag(tags, 'рынок', market);
          _tag(tags, 'ставка', rate);
      }

      // Цена не падает ниже нуля: при очень жёстких ползунках режем потерю.
      var local = market + rate;
      if (local < -0.95) {
        final k = -0.95 / local;
        market *= k;
        rate *= k;
        local = -0.95;
      }
      // Курс действует на уже изменившуюся цену.
      final fxPart = (1 + local) * fx * fxShare;
      _tag(tags, 'рубль', fxPart);
      if (tags.isEmpty) tags.add(const StressTag('нет влияния', 0));

      impacts.add(StressImpact(
        ticker: ticker,
        name: name,
        group: group,
        value: h.valueRub,
        market: h.valueRub * market,
        rate: h.valueRub * rate,
        fx: h.valueRub * fxPart,
        tags: tags,
      ));
    });

    final cash = CashService.summary().cash;
    if (cash > 0.5) {
      impacts.add(StressImpact(
        ticker: '',
        name: 'Свободные деньги',
        group: StressGroup.cash,
        value: cash,
        market: 0,
        rate: 0,
        fx: 0,
        tags: const [StressTag('рубли на счёте не меняются', 0)],
      ));
    }
    return StressResult(s, impacts);
  }

  /// Акции и фонды акций портфеля — для них считается бета по истории.
  static List<String> betaTickers() => [
        for (final t in AnalyticsService.currentHoldings().keys)
          if (_typeOf(t) == AssetType.stock ||
              (_typeOf(t) == AssetType.etf &&
                  !_moneyFunds.contains(t.toUpperCase()) &&
                  !_goldFunds.contains(t.toUpperCase()) &&
                  !_bondFunds.contains(t.toUpperCase())))
            t,
      ];
}
