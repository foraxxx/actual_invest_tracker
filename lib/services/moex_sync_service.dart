import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/purchase.dart';
import 'analytics_service.dart';
import 'currency_service.dart';
import 'favorites_service.dart';
import 'logo_service.dart';
import 'moex_service.dart';
import 'moex_trading_schedule_service.dart';
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
  final Set<String> _sectorBondsProcessed = {};
  bool _portfolioLogosStarted = false;
  bool _marketVisible = false;
  bool _fullMarketLoadedForSession = false;
  bool _fullRefreshPending = false;
  Completer<void>? _activeRefresh;
  bool _allPortfoliosBusy = false;
  Completer<void>? _allPortfoliosRefresh;

  /// Полный список бумаг с биржи, обновляется тем же циклом. Нужен экрану
  /// «Биржа», чтобы не ходить в сеть отдельно.
  static final ValueNotifier<Map<String, MoexQuote>> marketSnapshot = ValueNotifier({});

  /// Последние курсы валют с биржи — для вкладки «Биржа».
  static final ValueNotifier<Map<String, double>> currencyRates = ValueNotifier({});

  void start() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _restartTimer();
    // Первое обновление — сразу, чтобы не ждать целый интервал.
    unawaited(refreshNow());
    // И один полный обход по всем портфелям: иначе стартовый экран покажет
    // неактивные портфели по ценам с прошлого захода в них.
    unawaited(refreshAllPortfolios());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!OnlineSettingsService.enabled) return;
    final delay = MoexTradingScheduleService.nextAutomaticDelay(
      OnlineSettingsService.intervalSeconds,
    );
    // Вне торгов таймер спит до финального обновления либо следующего
    // открытия, вместо пробуждения телефона каждые несколько секунд.
    _timer = Timer(delay, () => unawaited(refreshNow()));
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

  /// Full market data is needed only while the Market tab is visible. Other
  /// screens refresh the portfolio and favourites through lightweight
  /// per-security requests.
  void setMarketVisible(bool visible) {
    if (_marketVisible == visible) return;
    _marketVisible = visible;
    if (visible && OnlineSettingsService.enabled) {
      unawaited(refreshNow(
        fullMarket: true,
        force: !_fullMarketLoadedForSession,
      ));
    }
  }

  /// Обновляет цены бумаг ИЗ ВСЕХ портфелей, а не только из активного.
  ///
  /// Обычный цикл обновления намеренно ограничен активным портфелем и
  /// избранным: запрос идёт по каждой бумаге отдельно, и тянуть все портфели
  /// каждые несколько секунд означало бы кратный рост трафика. Но тогда
  /// стоимость неактивных портфелей на стартовом экране остаётся такой, какой
  /// была при последнем заходе в них. Поэтому полный обход делается точечно:
  /// при запуске приложения и по жесту обновления на списке портфелей.
  Future<void> refreshAllPortfolios() async {
    if (!OnlineSettingsService.enabled) return;
    if (_allPortfoliosBusy) {
      // Уже идёт такой же обход — ждём его вместо второго параллельного.
      await _allPortfoliosRefresh?.future;
      return;
    }
    _allPortfoliosBusy = true;
    final completer = Completer<void>();
    _allPortfoliosRefresh = completer;
    refreshing.value = true;
    try {
      final tickers = await StorageService.allPortfolioTickers();
      if (tickers.isEmpty) return;
      final quotes = await MoexService.fetchQuotes(tickers: tickers);
      if (quotes.isEmpty) return;
      marketSnapshot.value = {...marketSnapshot.value, ...quotes};
      await OnlinePriceService.saveAll(quotes);
    } catch (_) {
      // Нет связи — на экране останутся последние известные цены. Портить
      // из-за этого запуск приложения ошибкой не стоит.
    } finally {
      _allPortfoliosBusy = false;
      refreshing.value = _busy;
      completer.complete();
      _allPortfoliosRefresh = null;
    }
  }

  /// Точечно получает последнюю доступную котировку выбранной бумаги.
  /// Используется формами, которым цена нужна сразу: запрос разрешён и вне
  /// торгов, поскольку MOEX тогда возвращает последнюю сделку/цену закрытия.
  Future<MoexQuote?> fetchQuote(String ticker) async {
    final key = ticker.trim().toUpperCase();
    if (key.isEmpty || !OnlineSettingsService.enabled) return null;
    try {
      final quotes = await MoexService.fetchQuotes(tickers: {key});
      final quote = quotes[key];
      if (quote == null) return null;
      marketSnapshot.value = {...marketSnapshot.value, key: quote};
      await OnlinePriceService.saveAll({key: quote});
      return quote;
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (OnlineSettingsService.enabled) {
        _restartTimer();
        unawaited(refreshNow());
        // Возврат из фона — тот же «вход в приложение»: список портфелей
        // должен показать актуальные суммы, а не те, что были при сворачивании.
        unawaited(refreshAllPortfolios());
      }
    } else {
      // Свернули приложение — тикать в фоне незачем.
      stop();
    }
  }

  Future<void> refreshNow({bool? fullMarket, bool force = false}) async {
    if (!OnlineSettingsService.enabled && !force) return;
    if (_busy) {
      if (force) {
        // Импорт и ручное обновление должны получить свежие цены, даже если в
        // этот момент заканчивается фоновый запрос. Дожидаемся его и запускаем
        // явное обновление следом.
        await _activeRefresh?.future;
        await refreshNow(fullMarket: fullMarket, force: true);
        return;
      }
      if (fullMarket == true) _fullRefreshPending = true;
      return;
    }
    _busy = true;
    final activeRefresh = Completer<void>();
    _activeRefresh = activeRefresh;
    refreshing.value = true;
    try {
      final tradingNow = MoexTradingScheduleService.isTradingSession();
      final finalRefresh = MoexTradingScheduleService.needsFinalRefresh(
        OnlineSettingsService.lastSyncAt,
      );
      if (!force && !tradingNow && !finalRefresh) {
        await _refreshReferenceDataIfNeeded();
        await _refreshSectorData(const {});
        _startPortfolioLogoRefresh();
        return;
      }

      final loadFullMarket = fullMarket ?? _marketVisible;
      final trackedTickers = <String>{
        ...AnalyticsService.currentHoldings().keys.map((ticker) => ticker.toUpperCase()),
        ...FavoritesService.all.map((ticker) => ticker.toUpperCase()),
      };
      final quotes = loadFullMarket
          ? await MoexService.fetchQuotes()
          : trackedTickers.isEmpty
              ? <String, MoexQuote>{}
              : await MoexService.fetchQuotes(tickers: trackedTickers);
      marketSnapshot.value = loadFullMarket
          ? quotes
          : <String, MoexQuote>{...marketSnapshot.value, ...quotes};
      if (loadFullMarket && quotes.isNotEmpty) {
        _fullMarketLoadedForSession = true;
      }

      // На диск кладём только то, что реально нужно между запусками: бумаги
      // портфеля и избранное. Писать в Hive несколько тысяч строк каждые
      // десять секунд — лишняя нагрузка, а весь рынок и так живёт в памяти,
      // пока приложение открыто.
      final toSave = <String, MoexQuote>{
        for (final e in quotes.entries)
          if (trackedTickers.contains(e.key)) e.key: e.value,
      };
      await OnlinePriceService.saveAll(toSave);

      // Курсы валют кладём в общую историю сегодняшней датой: валютные
      // операции пересчитываются по курсу на дату сделки, поэтому онлайн
      // может обновлять только сегодняшнюю точку. Всё, что раньше, остаётся
      // значением, введённым вручную.
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

      await _refreshSectorData(quotes);
      _startPortfolioLogoRefresh();

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
      if (!activeRefresh.isCompleted) activeRefresh.complete();
      if (identical(_activeRefresh, activeRefresh)) _activeRefresh = null;
      refreshing.value = false;
      if (_fullRefreshPending && _marketVisible) {
        _fullRefreshPending = false;
        unawaited(refreshNow(fullMarket: true));
      } else {
        _fullRefreshPending = false;
        _restartTimer();
      }
    }
  }

  Future<void> _refreshSectorData(Map<String, MoexQuote> quotes) async {
    // Базовую карту отраслей акций тянем один раз за сессию. Новые
    // облигации при этом обрабатываются при каждом обновлении отдельно.
    if (!_sectorsLoaded) {
      try {
        final sectors = await MoexService.fetchSectorMap();
        if (sectors.isNotEmpty) {
          SectorService.setExchangeSectors(sectors);
          _sectorsLoaded = true;
          // Если ранее использовалась резервная категория, после появления
          // базовой карты пробуем определить отрасль эмитента ещё раз.
          _sectorBondsProcessed.clear();
        }
      } catch (_) {
        _sectorsLoaded = false;
      }
    }
    await _enrichNewBondSectors(quotes);
  }

  void _startPortfolioLogoRefresh() {
    if (_portfolioLogosStarted || !OnlineSettingsService.enabled) return;
    _portfolioLogosStarted = true;
    unawaited(_refreshPortfolioLogos());
  }

  Future<void> _refreshPortfolioLogos() async {
    try {
      final holdings = AnalyticsService.currentHoldings().keys
          .map((ticker) => ticker.toUpperCase())
          .toSet();
      final names = <String, String>{};
      for (final trade in StorageService.purchases.reversed) {
        final ticker = trade.ticker.toUpperCase();
        if (holdings.contains(ticker) && !names.containsKey(ticker) && trade.name.trim().isNotEmpty) {
          names[ticker] = trade.name.trim();
        }
      }

      final missing = holdings
          .where((ticker) => LogoService.getPath(ticker) == null && !ticker.startsWith('SU'))
          .toList();
      // Небольшие группы: один медленный сайт эмитента не блокирует
      // весь портфель, но и открытые источники не получают десятки запросов сразу.
      for (var start = 0; start < missing.length; start += 3) {
        final batch = missing.skip(start).take(3);
        await Future.wait(batch.map((ticker) async {
          final quote = marketSnapshot.value[ticker];
          final isin = quote?.isin.isNotEmpty == true
              ? quote!.isin
              : await MoexService.isinOf(ticker);
          await LogoService.fetchIfMissing(
            ticker,
            isin: isin,
            companyName: names[ticker] ?? quote?.shortName,
          );
        }));
      }
    } finally {
      // Успешные логотипы уже закэшированы, а неудачные защищены своим
      // интервалом повтора. Разрешаем новый проход при следующей синхронизации.
      _portfolioLogosStarted = false;
    }
  }

  Future<void> _enrichNewBondSectors(Map<String, MoexQuote> quotes) async {
    final owned = AnalyticsService.allOwnedTickers().map((t) => t.toUpperCase()).toSet();
    final portfolioBonds = <String>{
      for (final trade in StorageService.purchases)
        if (trade.type == AssetType.bond) trade.ticker.toUpperCase(),
    };
    final snapshot = marketSnapshot.value;
    final additions = <String, String>{};

    for (final upper in owned) {
      final quote = quotes[upper] ?? snapshot[upper];
      final isBond = quote?.isBond == true || portfolioBonds.contains(upper);
      if (!isBond || _sectorBondsProcessed.contains(upper)) continue;

      var sector = upper.startsWith('SU')
          ? 'Государственные облигации'
          : 'Корпоративные облигации';
      try {
        // Связь выпуска с эмитентом подтверждается точным emitent_id.
        await MoexService.issuerInfoFor(upper);
        final issuerShare = await MoexService.issuerShareFor(upper);
        if (issuerShare != null) {
          final issuerSector = SectorService.sectorFor(issuerShare);
          if (issuerSector != 'Без сектора') sector = issuerSector;
        }
      } catch (_) {
        // Резервная категория полезнее, чем «Без сектора»; сетевой поиск
        // повторится после успешной загрузки базовой карты отраслей.
      }
      additions[upper] = sector;
      if (_sectorsLoaded) _sectorBondsProcessed.add(upper);
    }

    SectorService.mergeExchangeSectors(additions);
  }

  /// Купоны и дивиденды не зависят от того, открыта ли торговая сессия, но
  /// проверять их с частотой котировок тоже незачем.
  Future<void> _refreshReferenceDataIfNeeded() async {
    if (!OnlineSettingsService.referenceDataIsStale) return;
    await PayoutForecastService.refresh(force: true);
    await OnlineSettingsService.markReferenceSynced();
  }
}
