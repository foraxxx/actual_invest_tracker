import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Отметки о пройденном обучении — по одной на страницу.
///
/// Обучение показывается при первом заходе на каждый экран и больше там не
/// появляется. Хранится отдельно от портфелей: это свойство приложения, а не
/// конкретного портфеля.
class TourService {
  static const boxName = 'tour';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static bool isDone(String pageId) => _box.get(pageId) == '1';

  static Future<void> markDone(String pageId) async {
    await _box.put(pageId, '1');
    version.value++;
  }

  /// Совместимость с полноэкранным вводным туром.
  static Future<void> setCompleted(bool value) async {
    if (value) {
      await _box.put('intro', '1');
    } else {
      await _box.delete('intro');
    }
    version.value++;
  }

  /// Список пройденных страниц — для бэкапа.
  static List<String> get donePages =>
      _box.keys.map((k) => '$k').where((k) => _box.get(k) == '1').toList();

  static Future<void> restoreDonePages(List<String> pages) async {
    for (final p in pages) {
      await _box.put(p, '1');
    }
    version.value++;
  }

  /// Показать обучение заново — например, после сброса.
  static Future<void> resetAll() async {
    await _box.clear();
    version.value++;
  }
}
