import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/storage_service.dart';
import 'services/portfolio_service.dart';
import 'services/theme_service.dart';
import 'services/favorites_service.dart';
import 'services/currency_service.dart';
import 'services/tax_service.dart';
import 'services/sector_service.dart';
import 'services/manual_price_service.dart';
import 'services/logo_service.dart';
import 'services/appearance_service.dart';
import 'services/backup_crypto_service.dart';
import 'services/backup_settings_service.dart';
import 'services/moex_sync_service.dart';
import 'services/market_filter_service.dart';
import 'services/plan_filter_service.dart';
import 'services/online_price_service.dart';
import 'services/tour_service.dart';
import 'services/online_settings_service.dart';
import 'services/auto_backup_service.dart';
import 'screens/portfolios_screen.dart';
import 'design/app_theme.dart';

// Держим ссылку на верхнем уровне, чтобы слушатель жизненного цикла не был
// собран сборщиком мусора (AppLifecycleListener не привязан к дереву виджетов).
late final AppLifecycleListener appLifecycleListener;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  StorageService.registerAdapters();
  await PortfolioService.init(); // должен инициализироваться до StorageService/SectorService — они читают активный портфель
  await StorageService.init();
  await ThemeService.init();
  await FavoritesService.init();
  await CurrencyService.init();
  await TaxService.init();
  await SectorService.init();
  await ManualPriceService.init();
  await LogoService.init();
  await BackupSettingsService.init();
  await BackupCryptoService.init();
  await OnlineSettingsService.init();
  await OnlinePriceService.init();
  await TourService.init();
  await AppearanceService.init();
  await MarketFilterService.init();
  await PlanFilterService.init();

  // Убираем курсы, которые могли записаться с биржи по ошибке (своп-инструмент
  // вместо валютной пары давал значения вроде 0,08 ₽).
  await CurrencyService.dropImplausiblePoints();

  // Автообновление котировок стартует, только если пользователь его включил.
  if (OnlineSettingsService.enabled) MoexSyncService.instance.start();
  AutoBackupService.attach();
  unawaited(AutoBackupService.runNowIfEnabled());

  // "Вход и выход из приложения" на Android/iOS обычно НЕ перезапускают
  // процесс (main() не вызывается заново) — это просто сворачивание/разворачивание,
  // поэтому одного запуска при старте недостаточно: без этого слушателя
  // автобэкап срабатывал только на настоящий холодный старт. resumed —
  // вернулись в приложение, paused/detached — свернули или закрыли.
  appLifecycleListener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.resumed ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        unawaited(AutoBackupService.runNowIfEnabled());
      }
    },
  );

  // В release-сборке Flutter по умолчанию заменяет упавший виджет пустым
  // серым прямоугольником — на экране просто «ничего нет», и понять причину
  // невозможно. Показываем вместо этого читаемую карточку с текстом ошибки:
  // упавший блок остаётся видимым и сам рассказывает, что с ним не так.
  ErrorWidget.builder = (details) => _VisibleError(details: details);

  runApp(const InvestTrackerApp());
}

class _VisibleError extends StatelessWidget {
  final FlutterErrorDetails details;
  const _VisibleError({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x22FF4D6D),
        border: Border.all(color: const Color(0x66FF4D6D)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Этот блок не отрисовался',
            style: TextStyle(color: Color(0xFFFF4D6D), fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            details.exceptionAsString(),
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFF8FA3), fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class InvestTrackerApp extends StatelessWidget {
  const InvestTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Настройки оформления меняют саму тему, поэтому приложение
    // пересобирается целиком при их изменении.
    return ValueListenableBuilder<int>(
      valueListenable: AppearanceService.version,
      builder: (context, _, __) => ValueListenableBuilder<Color>(
        valueListenable: ThemeService.accentColor,
        builder: (context, accent, __) => ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.themeMode,
          builder: (context, mode, __) => MaterialApp(
            title: 'Invest Tracker',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(accent, Brightness.light),
            darkTheme: AppTheme.build(accent, Brightness.dark),
            themeMode: mode,
            // Моноширинные цифры проще всего раздать через стиль по
            // умолчанию: у TextTheme.apply такого параметра нет, а обычные
            // Text наследуют его, если сами не задают начертание цифр.
            builder: (context, child) => DefaultTextStyle.merge(
              style: TextStyle(
                fontFeatures: AppearanceService.monoDigits
                    ? const [FontFeature.tabularFigures()]
                    : const <FontFeature>[],
              ),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const PortfoliosScreen(),
          ),
        ),
      ),
    );
  }
}
