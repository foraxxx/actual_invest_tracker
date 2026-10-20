import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/purchase.dart';
import 'analytics_service.dart';
import 'appearance_service.dart';
import 'budget_service.dart';
import 'currency_service.dart';
import 'manual_price_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'portfolio_history_service.dart';
import 'portfolio_service.dart';
import 'storage_service.dart';

/// Виджет на экране телефона (Android).
///
/// Приложение готовит снимок: какие бумаги и сколько их, по какому режиму
/// торгов их искать на бирже, стоимость и прибыль на момент снимка, бюджет
/// и график. Дальше виджет живёт сам: раз в полчаса в торговые часы он
/// одним запросом на режим торгов берёт цены с биржи и пересчитывает
/// стоимость — без запуска приложения, поэтому почти не тратит батарею.
class HomeWidgetService {
  HomeWidgetService._();

  static const _channel = MethodChannel('invest_tracker/widget');
  static const _sourceKey = 'widgetSource';

  /// Источник «все портфели вместе».
  static const allId = 'all';

  static Timer? _timer;
  static bool _attached = false;
  static String? _lastSent;

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Что показывает виджет: [allId] или id портфеля. Если выбранный портфель
  /// удалили — все портфели.
  static String get source {
    final id = AppearanceService.ui(_sourceKey) ?? allId;
    if (id == allId) return allId;
    return PortfolioService.list.any((p) => p.id == id) ? id : allId;
  }

  static Future<void> setSource(String id) async {
    await AppearanceService.setUi(_sourceKey, id);
    schedule();
  }

  /// Подписывается на изменения данных. Снимок отправляется не чаще раза в
  /// несколько секунд: при обновлении котировок изменения идут пачкой.
  static void attach() {
    if (_attached || !_supported) return;
    _attached = true;
    final sources = <Listenable>[
      StorageService.dataVersion,
      OnlinePriceService.version,
      BudgetService.version,
      PortfolioService.version,
      AppearanceService.version,
      CurrencyService.version,
      PortfolioHistoryService.timeline,
    ];
    for (final s in sources) {
      s.addListener(schedule);
    }
    schedule();
  }

  static void schedule() {
    if (!_supported) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => unawaited(push()));
  }

  static Future<void> push() async {
    if (!_supported) return;
    try {
      final snap = await build();
      final json = jsonEncode(snap);
      if (json == _lastSent) return;
      await _channel.invokeMethod<void>('update', json);
      _lastSent = json;
    } catch (_) {
      // Виджет — дополнение: ошибка здесь не должна мешать приложению.
    }
  }

  static int _day(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Снимок для виджета. Суммы — в рублях.
  static Future<Map<String, dynamic>> build() async {
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

    for (final id in ids) {
      final data = await StorageService.readDataFor(id);
      profit += AnalyticsService.summaryFor(purchases: data.purchases, incomes: data.incomes).profitRub;

      final sorted = [...data.purchases]..sort(AnalyticsService.compareTrades);
      final qty = <String, double>{};
      final currency = <String, String>{};
      final lastPx = <String, double>{};
      final isBond = <String, bool>{};
      for (final p in sorted) {
        final t = p.ticker;
        currency[t] = p.currency;
        lastPx[t] = p.pricePerUnit;
        isBond[t] = p.type == AssetType.bond;
        final q = (qty[t] ?? 0) + (p.isSell ? -p.quantity : p.quantity);
        qty[t] = q < 0 ? 0 : q;
      }

      qty.forEach((t, q) {
        if (q <= 1e-9) return;
        final cur = currency[t] ?? 'RUB';
        final rate = CurrencyService.toRub(1, cur);
        final quote = online ? OnlinePriceService.get(t) : null;
        final market = quote == null ? null : _market(quote.board, isBond[t] ?? false);
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

    // График за месяц есть готовый только у открытого портфеля. Для всех
    // портфелей виджет копит точки сам — по одной в день.
    final chart = <List<num>>[];
    if (ids.length == 1 && ids.first == PortfolioService.activeId) {
      final from = DateTime.now().subtract(const Duration(days: 32));
      final byDay = <int, double>{};
      for (final e in PortfolioHistoryService.timeline.value) {
        if (e.key.isBefore(from)) continue;
        byDay[_day(e.key)] = e.value;
      }
      final days = byDay.keys.toList()..sort();
      for (final d in days) {
        chart.add([d, byDay[d]!]);
      }
    }

    return {
      'v': 1,
      'src': src,
      'title': title,
      'at': DateTime.now().millisecondsSinceEpoch,
      'pricesAt': (pricesAt ?? DateTime.now()).millisecondsSinceEpoch,
      'hidden': AppearanceService.hideAmounts,
      'fixed': fixed,
      'value': value,
      'profit': profit,
      'pos': positions.values.toList(),
      'chart': chart,
      'pay': _payouts(),
    };
  }

  /// Режим торгов бумаги на бирже: акции и фонды — shares, облигации —
  /// bonds. Неизвестный режим — цену виджет не обновляет, берёт из снимка.
  static String? _market(String board, bool bond) {
    if (board.isEmpty) return null;
    if (!board.startsWith('TQ') && board != 'SMAL') return null;
    return bond ? 'bonds' : 'shares';
  }

  /// Выплаты прошлого, текущего и следующего месяца: виджет сам выбирает,
  /// какая сейчас актуальна, — даже если приложение давно не открывали.
  static List<Map<String, dynamic>> _payouts() {
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
}
