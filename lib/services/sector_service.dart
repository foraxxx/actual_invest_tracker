import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/securities.dart';
import 'portfolio_service.dart';

/// Пользовательские секторы и привязка ценных бумаг к ним.
/// У одной бумаги может быть только один сектор. Если бумага не привязана
/// вручную, используется сектор из встроенного справочника (если есть),
/// иначе — "Без сектора".
///
/// Хранится отдельно на каждый портфель (см. PortfolioService) — у портфеля
/// по умолчанию бокс без суффикса (старые данные не мигрируют).
class SectorService {
  static const _listKey = '_custom_list';
  static late Box<String> _box; // _custom_list -> JSON-массив имён секторов; TICKER -> имя сектора

  static final ValueNotifier<int> version = ValueNotifier(0);

  static String _boxName(String portfolioId) =>
      portfolioId == PortfolioService.defaultId ? 'sectors' : 'sectors_$portfolioId';

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName(PortfolioService.activeId));
  }

  /// Вызывается PortfolioService при переключении портфеля.
  static Future<void> reopenBoxFor(String portfolioId) async {
    await _box.close();
    _box = await Hive.openBox<String>(_boxName(portfolioId));
    version.value++;
  }

  /// Удаляет с диска бокс секторов указанного портфеля.
  static Future<void> deleteBoxFor(String portfolioId) async {
    await Hive.deleteBoxFromDisk(_boxName(portfolioId));
  }

  static List<String> get customSectors {
    final raw = _box.get(_listKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  static Future<void> addSector(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = customSectors;
    if (list.contains(trimmed)) return;
    list.add(trimmed);
    await _box.put(_listKey, jsonEncode(list));
    version.value++;
  }

  static Future<void> removeSector(String name) async {
    final list = customSectors..remove(name);
    await _box.put(_listKey, jsonEncode(list));
    // отвязываем все бумаги, у которых был этот сектор
    for (final key in _box.keys.toList()) {
      if (key == _listKey) continue;
      if (_box.get(key) == name) await _box.delete(key);
    }
    version.value++;
  }

  /// Все секторы, доступные для выбора: пользовательские + встречающиеся
  /// во встроенном справочнике (без дублей)
  static List<String> get allAvailableSectors {
    final set = <String>{...customSectors};
    for (final s in SecuritiesDatabase.all) {
      if (s.sector.isNotEmpty) set.add(s.sector);
    }
    final list = set.toList()..sort();
    return list;
  }

  static Future<void> assignSector(String ticker, String? sector) async {
    final key = ticker.toUpperCase();
    if (sector == null || sector.isEmpty) {
      await _box.delete(key);
    } else {
      await _box.put(key, sector);
    }
    version.value++;
  }

  /// Итоговый сектор бумаги: ручная привязка > справочник > "Без сектора"
  /// Отрасли, собранные с биржи по составам отраслевых индексов. Живут в
  /// памяти и обновляются раз за сессию: это справочник, а не пользовательские
  /// данные, и хранить его на диске незачем.
  static Map<String, String> _fromExchange = {};

  static void setExchangeSectors(Map<String, String> map) {
    if (map.isEmpty) return;
    _fromExchange = map;
    version.value++;
  }

  static int get exchangeSectorCount => _fromExchange.length;

  static String sectorFor(String ticker) {
    final upper = ticker.toUpperCase();
    final manual = _box.get(upper);
    if (manual != null && manual.isNotEmpty) return manual;
    final fromDb = SecuritiesDatabase.byTicker(ticker)?.sector;
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;
    // Биржа знает отрасль далеко не всех бумаг, поэтому это последний
    // источник перед «Без сектора», а не первый.
    final fromExchange = _fromExchange[upper];
    if (fromExchange != null && fromExchange.isNotEmpty) return fromExchange;
    return 'Без сектора';
  }

  static String? manualSectorFor(String ticker) => _box.get(ticker.toUpperCase());

  /// Все ручные привязки тикер -> сектор (для бэкапа)
  static Map<String, String> get allAssignments {
    final map = <String, String>{};
    for (final key in _box.keys) {
      if (key == _listKey) continue;
      final value = _box.get(key);
      if (value != null) map[key as String] = value;
    }
    return map;
  }
}
