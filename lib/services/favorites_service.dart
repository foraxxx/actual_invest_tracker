import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Избранные бумаги. Хранится как box<bool> — примитивный тип Hive,
/// не требует регистрации адаптера.
class FavoritesService {
  static const boxName = 'favorites';
  static late Box<bool> _box;

  /// Уведомляет UI об изменении списка избранного
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<bool>(boxName);
  }

  static bool isFavorite(String ticker) => _box.get(ticker.toUpperCase(), defaultValue: false) ?? false;

  static Future<void> toggle(String ticker) async {
    final key = ticker.toUpperCase();
    if (isFavorite(key)) {
      await _box.delete(key);
    } else {
      await _box.put(key, true);
    }
    version.value++;
  }

  static List<String> get all => _box.keys.cast<String>().toList()..sort();
}
