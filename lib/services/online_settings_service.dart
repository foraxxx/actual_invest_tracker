import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Настройки загрузки данных с Московской биржи. По умолчанию всё выключено:
/// приложение остаётся полностью офлайновым, пока пользователь сам не решит
/// иначе.
class OnlineSettingsService {
  static const boxName = 'online_settings';
  static const _enabledKey = 'enabled';
  static const _lastSyncKey = 'lastSyncAt';
  static const _lastErrorKey = 'lastError';
  static const _lastCountKey = 'lastCount';
  static const _intervalKey = 'intervalSeconds';
  static const _lastReferenceSyncKey = 'lastReferenceSyncAt';

  static late Box<String> _box;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
  }

  /// По умолчанию включено: без котировок половина приложения бесполезна, а
  /// выключить загрузку можно в любой момент.
  static bool get enabled => _box.get(_enabledKey) != '0';

  /// Как часто обновлять котировки, в секундах. Биржа отдаёт данные с
  /// задержкой около 15 минут, поэтому чаще минуты смысла почти нет — но
  /// выбор оставлен за пользователем.
  static int get intervalSeconds => int.tryParse(_box.get(_intervalKey) ?? '') ?? 60;

  static Future<void> setIntervalSeconds(int v) async {
    await _box.put(_intervalKey, '$v');
    version.value++;
  }

  static DateTime? get lastSyncAt {
    final v = _box.get(_lastSyncKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  static DateTime? get lastReferenceSyncAt {
    final v = _box.get(_lastReferenceSyncKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  static bool get referenceDataIsStale {
    final last = lastReferenceSyncAt;
    return last == null || DateTime.now().difference(last) >= const Duration(hours: 24);
  }

  /// Сколько бумаг обновилось при последней успешной загрузке.
  static int get lastCount => int.tryParse(_box.get(_lastCountKey) ?? '') ?? 0;

  static String? get lastError => _box.get(_lastErrorKey);

  static Future<void> setEnabled(bool v) async {
    await _box.put(_enabledKey, v ? '1' : '0');
    if (!v) await _box.delete(_lastErrorKey);
    version.value++;
  }

  static Future<void> markSynced(int count) async {
    await _box.put(_lastSyncKey, DateTime.now().toIso8601String());
    await _box.put(_lastCountKey, '$count');
    await _box.delete(_lastErrorKey);
    version.value++;
  }

  static Future<void> markError(String message) async {
    await _box.put(_lastErrorKey, message);
    version.value++;
  }

  static Future<void> markReferenceSynced() async {
    await _box.put(_lastReferenceSyncKey, DateTime.now().toIso8601String());
  }
}
