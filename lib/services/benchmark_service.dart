import 'package:flutter/foundation.dart';

import 'moex_service.dart';
import 'moex_trading_schedule_service.dart';
import 'online_settings_service.dart';
import 'storage_service.dart';

/// Доходность широкого индекса MOEX за тот же интервал, что и история
/// портфеля. Значение служит бенчмарком для TWR и не влияет на расчёты.
class BenchmarkService {
  BenchmarkService._();

  static final ValueNotifier<double?> returnPercent = ValueNotifier(null);
  static final ValueNotifier<bool> loading = ValueNotifier(false);
  static final ValueNotifier<String?> error = ValueNotifier(null);

  static Future<void> refresh() async {
    if (loading.value || StorageService.purchases.isEmpty) {
      return;
    }
    if (!OnlineSettingsService.enabled) {
      error.value = 'Сравнение с IMOEX выключено';
      return;
    }
    if (!MoexTradingScheduleService.isTradingSession() &&
        !MoexTradingScheduleService.needsFinalRefresh(OnlineSettingsService.lastSyncAt)) {
      return;
    }
    loading.value = true;
    error.value = null;
    try {
      final firstDate = StorageService.purchases
          .map((p) => p.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final points = await MoexService.fetchIndexHistory(from: firstDate);
      if (points.length < 2 || points.first.value <= 0) {
        returnPercent.value = null;
        error.value = 'Данные IMOEX недоступны';
      } else {
        returnPercent.value =
            (points.last.value / points.first.value - 1) * 100;
      }
    } catch (_) {
      returnPercent.value = null;
      error.value = 'Нет связи с MOEX';
    } finally {
      loading.value = false;
    }
  }
}
