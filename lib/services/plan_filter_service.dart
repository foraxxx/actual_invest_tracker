import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Сохранённые фильтры экрана планов.
///
/// Хранится ровно один набор — тот, что был на экране, когда стояла галка
/// «Сохранить фильтры». Пока галка стоит, каждое изменение фильтров сразу
/// записывается сюда же, и при следующем открытии экран начинает с них.
/// Снятая галка стирает запись.
///
/// Сервис не знает, какие бывают фильтры: он хранит словарь, а смысл полям
/// даёт экран. Так добавление нового фильтра не требует правок здесь.
class PlanFilterService {
  PlanFilterService._();

  static const boxName = 'plan_filters';
  static const _key = 'saved';

  static late Box<String> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  /// Сохранённый набор или null, если сохранения нет (или оно битое).
  static Map<String, dynamic>? get saved {
    final raw = _box.get(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Битая запись фильтров не повод ломать экран — просто начинаем с чистых.
      return null;
    }
  }

  static Future<void> save(Map<String, dynamic> filters) => _box.put(_key, jsonEncode(filters));

  static Future<void> clear() => _box.delete(_key);
}
