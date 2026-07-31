import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Настройки автоматического бэкапа: папка на устройстве, куда приложение
/// само сохраняет JSON-бэкап при изменении данных, без участия пользователя.
class BackupSettingsService {
  static const boxName = 'backup_settings';
  static const _pathKey = 'path';
  static const _enabledKey = 'enabled';
  static const _lastKey = 'lastBackupAt';
  static const _errorKey = 'lastError';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  static String? get folderPath => _box.get(_pathKey);
  static bool get enabled => _box.get(_enabledKey) == '1';

  /// Текст последней ошибки автосохранения (например, "папка недоступна для
  /// записи"), если последняя попытка не удалась. Очищается при следующем
  /// успешном сохранении. Раньше сбои проглатывались молча — теперь их видно
  /// в настройках.
  static String? get lastError => _box.get(_errorKey);

  static DateTime? get lastBackupAt {
    final v = _box.get(_lastKey);
    return v == null ? null : DateTime.parse(v);
  }

  static Future<void> setFolderPath(String? path) async {
    if (path == null) {
      await _box.delete(_pathKey);
    } else {
      await _box.put(_pathKey, path);
    }
    await _box.delete(_errorKey);
    version.value++;
  }

  static Future<void> setEnabled(bool v) async {
    await _box.put(_enabledKey, v ? '1' : '0');
    version.value++;
  }

  static Future<void> markBackedUp() async {
    await _box.put(_lastKey, DateTime.now().toIso8601String());
    await _box.delete(_errorKey);
    version.value++;
  }

  static Future<void> markError(String message) async {
    await _box.put(_errorKey, message);
    version.value++;
  }
}
