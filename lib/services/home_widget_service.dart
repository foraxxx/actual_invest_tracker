import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/income.dart';
import '../models/purchase.dart';
import 'analytics_service.dart';
import 'appearance_service.dart';
import 'budget_service.dart';
import 'currency_service.dart';
import 'home_widget_config.dart';
import 'manual_price_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'payout_forecast_service.dart';
import 'portfolio_history_service.dart';
import 'portfolio_service.dart';
import 'storage_service.dart';

/// Виджет на экране телефона (Android).
///
/// Приложение готовит снимок: какие бумаги и сколько их, по какому режиму
/// торгов их искать на бирже, стоимость и прибыль на момент снимка, график
/// за месяц, бюджет, ближайшие выплаты и настройки конструктора. Дальше
/// виджет живёт сам: раз в полчаса в торговые часы он одним запросом на
/// режим торгов берёт цены с биржи и пересчитывает стоимость — без запуска
/// приложения, поэтому почти не тратит батарею.
class HomeWidgetService {
  HomeWidgetService._();

  static const _channel = MethodChannel('invest_tracker/widget');
  static const _configKey = 'widgetConfig';
  static const _legacySourceKey = 'widgetSource';

  /// Источник «все портфели вместе».
  static const allId = 'all';

  static Timer? _timer;
  static bool _attached = false;
  static String? _lastSent;

  /// Последний снимок — для превью в конструкторе.
  static final ValueNotifier<Map<String, dynamic>?> lastSnapshot = ValueNotifier(null);

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static WidgetConfig get config =>
      WidgetConfig.decode(AppearanceService.ui(_configKey), AppearanceService.ui(_legacySourceKey) ?? allId);

  static Future<void> setConfig(WidgetConfig c) async {
    await AppearanceService.setUi(_configKey, c.encode());
    schedule(quick: true);
  }

  /// Что показывает виджет: [allId] или id портфеля. Если выбранный портфель
  /// удалили — все портфели.
  static String get source {
    final id = config.source;
    if (id == allId) return allId;
    return PortfolioService.list.any((p) => p.id == id) ? id : allId;
  }

  /// Подписывается на изменения данных. Снимок отправляется не чаще раза в
  /// несколько секунд: при обновлении котировок изменения идут пачкой.
  static void attach() {
    if (_attached) return;
    _attached = true;
    final sources = <Listenable>[
      StorageService.dataVersion,
      OnlinePriceService.version,
      BudgetService.version,
      PortfolioService.version,
      AppearanceService.version,
      CurrencyService.version,
    ];
    for (final s in sources) {
      s.addListener(schedule);
    }
    schedule();
  }

  static void schedule({bool quick = false}) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: quick ? 300 : 3000), () => unawaited(push()));
  }

  static Future<void> push() async {
    try {
      final snap = await build();
      lastSnapshot.value = snap;
      if (!_supported) return;
      // Время снимка меняется всегда — сравниваем без него.
      final body = jsonEncode(snap..remove('at'));
      if (body == _lastSent) return;
      snap['at'] = DateTime.now().millisecondsSinceEpoch;
      await _channel.invokeMethod<void>('update', jsonEncode(snap));
      _lastSent = body;
    } catch (_) {
      // Виджет — дополнение: ошибка здесь не должна мешать приложению.
    }
  }

  static int _day(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static const _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  /// Снимок для виджета. Суммы — в рублях.
  static Future<Map<String, dynamic>> build() async {
    final cfg = config;
    final src = source;
    final metas = PortfolioService.list;
    final ids = src == allId ? [for (final m in metas) m.id] : [src];
    final title = src == allId
        ? (metas.length > 1 ? 'Все портфели' : metas.first.name)
        : metas.firstWhere((m) => m.id == src).name;

    final online = OnlineSettingsService.enabled;
    double fixed = 0;
    double profit = 0;
    DateTime? pricesAt;
    final positions = <String, Map<String, dynamic>>{};
    final allTrades = <Purchase>[];
    final held = <String, double>{};
    final currencyOf = <String, String>{};

    for (final id in ids) {
      final data = await _read(id);
      allTrades.addAll(data.purchases);
      profit += AnalyticsService.summaryFor(purchases: data.purchases, incomes: data.incomes).profitRub;

      final sorted = [...data.purchases]..sort(AnalyticsService.compareTrades);
      final qty = <String, double>{};
      final lastPx = <String, double>{};
      final isBond = <String, bool>{};
      for (final p in sorted) {
        final t = p.ticker;
        currencyOf[t] = p.currency;
        lastPx[t] = p.pricePerUnit;
        isBond[t] = p.type == AssetType.bond;
        final q = (qty[t] ?? 0) + (p.isSell ? -p.quantity : p.quantity);
        qty[t] = q < 0 ? 0 : q;
      }

      qty.forEach((t, q) {
        if (q <= 1e-9) return;
        held[t] = (held[t] ?? 0) + q;
        final cur = currencyOf[t] ?? 'RUB';
        final rate = CurrencyService.toRub(1, cur);
        final quote = online ? OnlinePriceService.get(t) : null;
        final bond = isBond[t] ?? false;
        final market = quote == null ? null : _market(quote.board, bond);
        if (quote == null || market == null) {
          final px = ManualPriceService.get(t) ?? lastPx[t] ?? 0;
          fixed += q * px * rate;
          return;
        }
        if (pricesAt == null || quote.fetchedAt.isAfter(pricesAt!)) pricesAt = quote.fetchedAt;
        final key = t.toUpperCase();
        final prev = positions[key];
        if (prev != null) {
          prev['q'] = (prev['q'] as double) + q;
          return;
        }
        positions[key] = {
          's': key,
          'n': bond && quote.shortName.isNotEmpty ? quote.shortName : key,
          'b': quote.board,
          'm': market,
          'q': q,
          'k': rate,
          'p': quote.price,
          if (quote.prevClose != null) 'c': quote.prevClose,
        };
      });
    }

    double value = fixed;
    for (final p in positions.values) {
      value += (p['q'] as double) * (p['p'] as double) * (p['k'] as double);
    }

    final now = DateTime.now();
    final month = BudgetService.started ? BudgetService.view(now.year, now.month) : null;

    return {
      'v': 2,
      'src': src,
      'title': title,
      'at': now.millisecondsSinceEpoch,
      'pricesAt': (pricesAt ?? now).millisecondsSinceEpoch,
      'hidden': AppearanceService.hideAmounts,
      'fixed': fixed,
      'value': value,
      'profit': profit,
      'pos': positions.values.toList(),
      'chart': online ? await _chart(src, allTrades) : const <List<num>>[],
      'pay': _budgetPayouts(),
      if (month != null && month.plannedTotal > 0.5)
        'month': {'n': _monthNames[now.month - 1], 'plan': month.plannedTotal, 'done': month.doneTotal},
      'divs': _upcoming(held, currencyOf, positions),
      'cfg': {
        'st': cfg.style.toJson(),
        'sz': {for (final s in WidgetSize.values) s.name: cfg.of(s).toJson()},
      },
    };
  }

  /// Данные других портфелей меняются редко, а чтение с диска заметно
  /// дороже расчёта. Открытый портфель читается всегда из памяти, остальные —
  /// не чаще раза в 10 минут или после изменений в списке портфелей.
  static final Map<String, (String, DateTime, ({List<Purchase> purchases, List<Income> incomes}))> _dataCache = {};

  static Future<({List<Purchase> purchases, List<Income> incomes})> _read(String id) async {
    if (id == PortfolioService.activeId) return StorageService.readDataFor(id);
    final stamp = '${PortfolioService.version.value}|${PortfolioService.activeId}';
    final hit = _dataCache[id];
    if (hit != null && hit.$1 == stamp && DateTime.now().difference(hit.$2).inMinutes < 10) return hit.$3;
    final data = await StorageService.readDataFor(id);
    _dataCache[id] = (stamp, DateTime.now(), data);
    return data;
  }

  /// Режим торгов бумаги на бирже: акции и фонды — shares, облигации —
  /// bonds. Неизвестный режим — цену виджет не обновляет, берёт из снимка.
  static String? _market(String board, bool bond) {
    if (board.isEmpty) return null;
    if (!board.startsWith('TQ') && board != 'SMAL') return null;
    return bond ? 'bonds' : 'shares';
  }

  // --- График за месяц ---

  static String? _chartKey;
  static List<List<num>> _chartCache = const [];

  /// Стоимость на закрытие каждого дня за последний месяц, без сегодняшнего
  /// дня (его виджет считает сам по свежим ценам). Считается один раз в день
  /// и заново — только когда поменялись сделки или выбранный портфель.
  static Future<List<List<num>>> _chart(String src, List<Purchase> trades) async {
    final now = DateTime.now();
    final key = '$src|${StorageService.dataVersion.value}|${PortfolioService.version.value}|${_day(now)}';
    if (key == _chartKey) return _chartCache;
    try {
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 32));
      final points = await PortfolioHistoryService.valueHistory(trades, from: from) ?? const [];
      final today = _day(now);
      final byDay = <int, double>{};
      for (final e in points) {
        final d = _day(e.key);
        if (d < today) byDay[d] = e.value;
      }
      final days = byDay.keys.toList()..sort();
      _chartCache = [
        for (final d in days) [d, byDay[d]!],
      ];
      _chartKey = key;
    } catch (_) {
      // Без сети графика просто не будет — виджет покажет подсказку.
    }
    return _chartCache;
  }

  // --- Бюджет ---

  /// Выплаты прошлого, текущего и следующего месяца: виджет сам выбирает,
  /// какая сейчас актуальна, — даже если приложение давно не открывали.
  /// Даты уже с переносом на рабочий день.
  static List<Map<String, dynamic>> _budgetPayouts() {
    if (!BudgetService.started) return const [];
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (int k = -1; k <= 1; k++) {
      final m = DateTime(now.year, now.month + k);
      final view = BudgetService.view(m.year, m.month);
      for (int i = 0; i < 2; i++) {
        result.add({
          'n': view.config.names[i],
          'd': _day(view.payDate(i)),
          'plan': view.planned(i),
          'left': view.leftFor(i),
        });
      }
    }
    return result;
  }

  // --- Ближайшие выплаты по бумагам ---

  /// До трёх ближайших дивидендов и купонов с объявленной датой — на
  /// нынешнее количество бумаг, в рублях до налога.
  static List<Map<String, dynamic>> _upcoming(
    Map<String, double> held,
    Map<String, String> currencyOf,
    Map<String, Map<String, dynamic>> positions,
  ) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final items = <(DateTime, Map<String, dynamic>)>[];
    held.forEach((ticker, qty) {
      final payouts = PayoutForecastService.payoutsFor(ticker)
          .where((p) => p.kind == 'Купон' || p.kind == 'Дивиденд')
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      double lastCoupon = 0;
      for (final p in payouts) {
        if (p.date.isBefore(start)) {
          if (p.kind == 'Купон' && p.amount > 0) lastCoupon = p.amount;
          continue;
        }
        if (!p.dateKnown) continue;
        final perUnit = p.amount > 0 ? p.amount : (p.kind == 'Купон' ? lastCoupon : 0.0);
        if (perUnit <= 0) continue;
        final raw = p.currency.toUpperCase();
        final currency = (raw == 'SUR' || raw.isEmpty) ? 'RUB' : raw;
        final key = ticker.toUpperCase();
        items.add((
          p.date,
          {
            'n': positions[key]?['n'] ?? key,
            'k': p.kind == 'Купон' ? 'купон' : 'дивиденд',
            'd': _day(p.date),
            'rub': CurrencyService.toRub(perUnit * qty, currency),
          },
        ));
        break;
      }
    });
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final i in items.take(3)) i.$2];
  }
}
