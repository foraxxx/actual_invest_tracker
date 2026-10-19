import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'moex_service.dart';
import 'online_settings_service.dart';

/// Бета акции — насколько сильно она двигается вместе с рынком: 1 — как
/// индекс МосБиржи, 1.5 — в полтора раза сильнее, 0.5 — вдвое спокойнее.
///
/// Считается по недельным ценам за два года относительно индекса. Хранится
/// на телефоне и обновляется раз в месяц: бета меняется медленно.
class BetaService {
  BetaService._();

  static const boxName = 'betas';
  static Box<String>? _box;
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  /// Бета по истории или null, если её ещё не посчитали или истории мало.
  static double? betaOf(String ticker) {
    final raw = _box?.get(ticker.toUpperCase());
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      return (m['b'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  static DateTime? _checkedAt(String ticker) {
    final raw = _box?.get(ticker.toUpperCase());
    if (raw == null) return null;
    try {
      return DateTime.tryParse('${(jsonDecode(raw) as Map)['at']}');
    } catch (_) {
      return null;
    }
  }

  static bool _loading = false;

  /// Досчитывает бету для бумаг, у которых её нет или она старше месяца.
  static Future<void> refresh(Iterable<String> tickers) async {
    if (_loading || _box == null || !OnlineSettingsService.enabled) return;
    final now = DateTime.now();
    final todo = [
      for (final t in tickers.map((e) => e.toUpperCase()).toSet())
        if (_checkedAt(t) == null || now.difference(_checkedAt(t)!) > const Duration(days: 30)) t,
    ];
    if (todo.isEmpty) return;
    _loading = true;
    try {
      final from = DateTime(now.year - 2, now.month, now.day);
      final index = await MoexService.fetchCandles(
        engine: 'stock',
        market: 'index',
        secId: 'IMOEX',
        from: from,
        interval: 7,
      );
      if (index.length < 30) return;
      var changed = false;
      for (final t in todo) {
        try {
          final prices = await MoexService.fetchSecurityCandles(t, from: from, interval: 7, market: 'shares');
          final beta = estimate(prices, index);
          await _box!.put(t, jsonEncode({'b': beta, 'at': now.toIso8601String()}));
          changed = true;
        } catch (_) {
          // Одна бумага без истории не мешает остальным.
        }
      }
      if (changed) version.value++;
    } catch (_) {
      // Без сети стресс-тест считает по средним для отрасли.
    } finally {
      _loading = false;
    }
  }

  static void refreshInBackground(Iterable<String> tickers) => unawaited(refresh(tickers));

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Бета по недельным закрытиям бумаги и индекса. Недели сопоставляются по
  /// дате начала; нужно хотя бы 30 общих недель, иначе null.
  @visibleForTesting
  static double? estimate(List<MapEntry<DateTime, double>> prices, List<MapEntry<DateTime, double>> index) {
    final idx = {for (final p in index) _day(p.key): p.value};
    final pairs = <(double, double)>[];
    for (final p in prices) {
      final i = idx[_day(p.key)];
      if (i != null && i > 0 && p.value > 0) pairs.add((p.value, i));
    }
    final xs = <double>[];
    final ys = <double>[];
    for (int k = 1; k < pairs.length; k++) {
      ys.add(math.log(pairs[k].$1 / pairs[k - 1].$1));
      xs.add(math.log(pairs[k].$2 / pairs[k - 1].$2));
    }
    if (xs.length < 30) return null;
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    double cov = 0;
    double varX = 0;
    for (int k = 0; k < xs.length; k++) {
      cov += (xs[k] - mx) * (ys[k] - my);
      varX += (xs[k] - mx) * (xs[k] - mx);
    }
    if (varX <= 0) return null;
    return cov / varX;
  }
}
