import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'moex_service.dart';
import 'moex_sync_service.dart';
import 'online_settings_service.dart';

/// Цена бумаги за последние 30 дней — для мини-графика в составе портфеля.
///
/// Нужна только форма линии, поэтому хватает дневных свечей. Сохраняется
/// между запусками и обновляется не чаще раза в день: восемь бумаг — восемь
/// маленьких запросов в сутки, а не при каждом открытии главной.
///
/// Кэш общий для всех портфелей: история цены не зависит от того, в каком
/// портфеле лежит бумага.
class MiniHistoryService {
  MiniHistoryService._();

  static const boxName = 'mini_history';
  static const days = 30;

  static late Box<String> _box;

  /// Растёт после каждой загруженной истории — главная перерисовывает строки.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static final Map<String, List<double>> _memory = {};
  static bool _busy = false;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Цены закрытия по дням, старые слева. null — истории нет.
  static List<double>? pointsFor(String ticker) {
    final key = ticker.toUpperCase();
    final cached = _memory[key];
    if (cached != null) return cached.length < 2 ? null : cached;
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = (map['p'] as List).map((e) => (e as num).toDouble()).toList();
      _memory[key] = list;
      return list.length < 2 ? null : list;
    } catch (_) {
      return null;
    }
  }

  static bool _freshToday(String ticker) {
    final raw = _box.get(ticker.toUpperCase());
    if (raw == null) return false;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['d'] == _today();
    } catch (_) {
      return false;
    }
  }

  /// Догружает историю бумаг, у которых её нет или она вчерашняя. Запросы идут
  /// по одному, чтобы не создавать пачку параллельных обращений к бирже.
  static Future<void> refresh(Iterable<String> tickers, {bool force = false}) async {
    if (!OnlineSettingsService.enabled || _busy) return;
    _busy = true;
    try {
      for (final ticker in tickers.toList()) {
        if (!force && _freshToday(ticker)) continue;
        final key = ticker.toUpperCase();
        try {
          final quote = MoexSyncService.marketSnapshot.value[key];
          final points = await MoexService.fetchSecurityCandles(
            key,
            from: DateTime.now().subtract(const Duration(days: days + 5)),
            interval: 24,
            maxRows: 500,
            market: quote?.market.isNotEmpty == true ? quote!.market : null,
          );
          final from = DateTime.now().subtract(const Duration(days: days));
          final values = points.where((e) => !e.key.isBefore(from)).map((e) => e.value).toList();
          _memory[key] = values;
          await _box.put(key, jsonEncode({'d': _today(), 'p': values}));
          version.value++;
        } catch (_) {
          // Нет связи или бумага не торгуется — строка просто останется без
          // линии, остальные бумаги грузим дальше.
        }
      }
    } finally {
      _busy = false;
    }
  }
}
