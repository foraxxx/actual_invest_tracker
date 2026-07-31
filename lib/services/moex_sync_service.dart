import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/purchase.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'favorites_service.dart';
import 'moex_service.dart';
import 'network_service.dart';
import 'online_price_service.dart';
import 'online_settings_service.dart';
import 'payout_forecast_service.dart';
import 'sector_service.dart';
import 'storage_service.dart';

/// Автообновление котировок по таймеру.
///
/// Два правила, без которых это быстро съело бы батарею и трафик:
/// работаем только когда приложение на экране (`AppLifecycleState.resumed`),
/// и никогда не запускаем новый запрос, пока не завершился предыдущий —
/// на медленной сети запросы иначе наложатся друг на друга.
class MoexSyncService with WidgetsBindingObserver {
  MoexSyncService._();

  static final MoexSyncService instance = MoexSyncService._();

  static final ValueNotifier<bool> refreshing = ValueNotifier(false);

  Timer? _timer;
  bool _busy = false;
  bool _observing = false;
  bool _sectorsLoaded = false;

  /// Полный список бумаг с биржи, обновляется тем же циклом. Нужен экрану
  /// «Биржа», чтобы не ходить в сеть отдельно.
  static final ValueNotifier<Map<String, MoexQuote>> marketSnapshot = ValueNotifier({});

  /// Последние курсы валют с биржи — для вкладки «Биржа».
  static final ValueNotifier<Map<String, double>> currencyRates = ValueNotifier({});

  void start() {
    // Проверяем VPN сразу, а не только когда запрос уже сорвался: иначе
    // подсказка появлялась бы с задержкой или не появлялась вовсе.
    unawaited(NetworkService.checkVpn());
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _restartTimer();
    // Первое обновление — сразу, чтобы не ждать целый интервал.
    unawaited(refreshNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!OnlineSettingsService.enabled) return;
    final seconds = OnlineSettingsService.intervalSeconds;
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => unawaited(refreshNow()));
  }

  /// Вызывается после изменения настроек: включили/выключили или сменили
  /// интервал.
  void applySettings() {
    if (OnlineSettingsService.enabled) {
      start();
    } else {
      stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (OnlineSettingsService.enabled) {
        _restartTimer();
        unawaited(refreshNow());
      }
    } else {
      // Свернули приложение — тикать в фоне незачем.
      stop();
    }
  }

  Future<void> refreshNow() async {
    if (_busy || !OnlineSettingsService.enabled) return;
    _busy = true;
    refreshing.value = true;
    try {
      final quotes = await MoexService.fetchQuotes();
      marketSnapshot.value = quotes;

      // На диск кладём только то, что реально нужно между запусками: бумаги
      // портфеля и избранное. Писать в Hive несколько тысяч строк каждые
      // десять секунд — лишняя нагрузка, а весь рынок и так живёт в памяти,
      // пока приложение открыто.
      final keep = <String>{
        ...AnalyticsService.allOwnedTickers(),
        ...FavoritesService.all,
      };
      final toSave = <String, MoexQuote>{
        for (final e in quotes.entries)
          if (keep.contains(e.key)) e.key: e.value,
      };
      await OnlinePriceService.saveAll(toSave);

      // Курсы валют кладём в общую историю сегодняшней датой: валютные
      // операции пересчитываются по курсу на дату сделки, поэтому онлайн
      // может обновлять только сегодняшнюю точку. Всё, что раньше, остаётся
      // тем, что ты ввёл руками.
      try {
        final rates = await MoexService.fetchCurrencyRates();
        currencyRates.value = rates;
        for (final e in rates.entries) {
          // Каждые десять секунд перезаписывать одно и то же значение незачем.
          if (e.value < CurrencyService.minPlausibleRate) continue;
          if ((CurrencyService.currentRate(e.key) - e.value).abs() > 0.0001) {
            await CurrencyService.setRateAt(e.key, DateTime.now(), e.value);
          }
        }
      } catch (_) {
        // Курсы — не главное: если не приехали, котировки всё равно обновились.
      }

      // Отрасли меняются раз в квартал — тянем один раз за сессию.
      if (!_sectorsLoaded) {
        _sectorsLoaded = true;
        try {
          final sectors = await MoexService.fetchSectorMap();
          // Сначала публикуем отрасли акций. Затем для облигаций портфеля
          // находим акцию того же эмитента и наследуем её отрасль.
          SectorService.setExchangeSectors(sectors);
          final enriched = Map<String, String>.from(sectors);
          final owned = AnalyticsService.allOwnedTickers();
          final portfolioBonds = <String>{
            for (final trade in StorageService.purchases)
              if (trade.type == AssetType.bond) trade.ticker.toUpperCase(),
          };
          for (final ticker in owned) {
            final upper = ticker.toUpperCase();
            final quote = quotes[upper];
            final isBond = quote?.isBond == true || portfolioBonds.contains(upper);
            if (!isBond || enriched.containsKey(upper)) continue;

            // Resolve the issuer by MOEX emitent_id. issuerShareFor only
            // returns a share whose emitent_id exactly matches the bond's,
            // so similarly named unrelated companies cannot leak a sector.
            await MoexService.issuerInfoFor(upper);
            final issuerShare = await MoexService.issuerShareFor(upper);
            if (issuerShare != null) {
              final issuerSector = SectorService.sectorFor(issuerShare);
              if (issuerSector != 'Без сектора') {
                enriched[upper] = issuerSector;
                continue;
              }
            }

            // Для выпусков без публичной акции оставляем полезную категорию,
            // а не безликое «Без сектора».
            enriched[upper] = upper.startsWith('SU')
                ? 'Государственные облигации'
                : 'Корпоративные облигации';
          }
          SectorService.setExchangeSectors(enriched);
        } catch (_) {
          _sectorsLoaded = false;
        }
      }

      // Графики купонов и дивидендов подтягиваем один раз для новых бумаг:
      // они известны заранее и меняются редко.
      unawaited(PayoutForecastService.refresh());

      await OnlineSettingsService.markSynced(quotes.length);
    } catch (e) {
      // Частая причина — включённый VPN: до биржи запрос просто не доходит.
      await NetworkService.checkVpn();
      await OnlineSettingsService.markError('$e');
    } finally {
      _busy = false;
      refreshing.value = false;
    }
  }
}
