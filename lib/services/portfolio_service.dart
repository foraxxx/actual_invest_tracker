import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';
import 'sector_service.dart';

/// Статус портфеля: активен (в работе) или закрыт (архивный, но не удалён).
/// Это отдельно от того, какой портфель сейчас ВЫБРАН (см. activeId/switchTo)
/// — можно закрыть портфель и продолжать какое-то время в нём находиться,
/// или наоборот держать закрытые портфели просто для истории.
enum PortfolioStatus { active, closed }

/// Метаданные одного портфеля — сами данные (сделки/доходы/планы/секторы)
/// физически лежат в отдельных Hive-боксах, см. StorageService/SectorService.
class PortfolioMeta {
  final String id;
  String name;
  final DateTime createdAt;
  PortfolioStatus status;

  PortfolioMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    this.status = PortfolioStatus.active,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
      };

  factory PortfolioMeta.fromJson(Map<String, dynamic> j) => PortfolioMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        // старые сохранённые записи без поля status — считаем активными
        status: j['status'] != null
            ? PortfolioStatus.values.byName(j['status'] as String)
            : PortfolioStatus.active,
      );
}

/// Управляет списком портфелей и тем, какой из них сейчас активен.
/// "Портфель" здесь — это просто отдельный набор Hive-боксов с суффиксом
/// его id; переключение портфеля значит закрыть текущие боксы и открыть
/// боксы нужного портфеля в StorageService и SectorService.
///
/// Портфель [defaultId] — это тот, что был в приложении всегда, до появления
/// множественных портфелей: его боксы — без суффикса, поэтому апгрейд со
/// старой версии ничего не мигрирует и не теряет.
class PortfolioService {
  static const defaultId = 'default';
  static const _boxName = 'portfolios_meta';
  static const _listKey = '_list';
  static const _activeKey = '_active';

  static late Box<String> _box;

  /// Меняется при создании/переименовании/удалении портфеля и при
  /// переключении активного — экраны слушают это, чтобы перерисоваться.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    if (list.isEmpty) {
      await _saveList([PortfolioMeta(id: defaultId, name: 'Основной', createdAt: DateTime.now())]);
      await _box.put(_activeKey, defaultId);
    }
  }

  static List<PortfolioMeta> get list {
    final raw = _box.get(_listKey);
    if (raw == null) return [];
    final arr = jsonDecode(raw) as List;
    return arr.map((e) => PortfolioMeta.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _saveList(List<PortfolioMeta> l) async {
    await _box.put(_listKey, jsonEncode(l.map((p) => p.toJson()).toList()));
  }

  static String get activeId => _box.get(_activeKey) ?? defaultId;

  static PortfolioMeta get active {
    final l = list;
    return l.firstWhere((p) => p.id == activeId, orElse: () => l.first);
  }

  /// Создаёт новый (пустой) портфель. Не переключает на него автоматически —
  /// вызови switchTo, если нужно сразу перейти.
  static Future<PortfolioMeta> create(String name) async {
    final meta = PortfolioMeta(id: const Uuid().v4(), name: name.trim(), createdAt: DateTime.now());
    final l = list..add(meta);
    await _saveList(l);
    version.value++;
    return meta;
  }

  static Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final l = list;
    final p = l.firstWhere((x) => x.id == id);
    p.name = trimmed;
    await _saveList(l);
    version.value++;
  }

  /// Меняет статус портфеля (активен/закрыт) — не влияет на то, какой
  /// портфель сейчас выбран, и не удаляет данные.
  static Future<void> setStatus(String id, PortfolioStatus status) async {
    final l = list;
    final p = l.firstWhere((x) => x.id == id);
    p.status = status;
    await _saveList(l);
    version.value++;
  }

  /// Переключает активный портфель: закрывает текущие боксы данных и
  /// открывает боксы выбранного портфеля (создаются пустыми, если это
  /// первое переключение на новый портфель).
  static Future<void> switchTo(String id) async {
    if (id == activeId) return;
    await _box.put(_activeKey, id);
    await StorageService.reopenBoxesFor(id);
    await SectorService.reopenBoxFor(id);
    version.value++;
  }

  /// Удаляет портфель целиком — вместе со всеми его данными (без возможности
  /// восстановления). Нельзя удалить последний оставшийся портфель. Если
  /// удаляется активный — приложение автоматически переключается на первый
  /// из оставшихся.
  static Future<void> delete(String id) async {
    final l = list;
    if (l.length <= 1) return;
    final wasActive = id == activeId;

    l.removeWhere((p) => p.id == id);
    await _saveList(l);

    if (wasActive) {
      final newActiveId = l.first.id;
      await _box.put(_activeKey, newActiveId);
      await StorageService.reopenBoxesFor(newActiveId);
      await SectorService.reopenBoxFor(newActiveId);
    }

    await StorageService.deleteBoxesFor(id);
    await SectorService.deleteBoxFor(id);
    version.value++;
  }
}
