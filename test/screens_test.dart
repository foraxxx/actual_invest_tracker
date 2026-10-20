// Проверки экранов: окно открывается без ошибок и ничего не вылезает за
// край на узком телефоне. Если вёрстка сломается — «overflowed» или
// исключение при построении, — тест упадёт ещё до установки приложения.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/design/app_theme.dart';
import 'package:invest_tracker/models/purchase.dart';
import 'package:invest_tracker/services/analytics_service.dart';
import 'package:invest_tracker/services/appearance_service.dart';
import 'package:invest_tracker/services/cbr_service.dart';
import 'package:invest_tracker/services/currency_service.dart';
import 'package:invest_tracker/services/manual_price_service.dart';
import 'package:invest_tracker/services/online_price_service.dart';
import 'package:invest_tracker/services/online_settings_service.dart';
import 'package:invest_tracker/services/portfolio_service.dart';
import 'package:invest_tracker/services/sector_service.dart';
import 'package:invest_tracker/services/storage_service.dart';
import 'package:invest_tracker/widgets/choice_cards.dart';
import 'package:invest_tracker/widgets/real_return_sheet.dart';
import 'package:invest_tracker/widgets/stress_test_sheet.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Шрифт по ширине близок к настоящему: со стандартным тестовым шрифтом
    // каждая буква шириной в квадрат, и тесты ругались бы на переполнение,
    // которого на телефоне нет.
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/DejaVuSansCondensed.ttf'))
      ..addFont(rootBundle.load('assets/fonts/DejaVuSansCondensed-Bold.ttf'));
    await loader.load();

    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_screens_test_');
    Hive.init(hiveDir.path);
    StorageService.registerAdapters();
    await PortfolioService.init();
    await StorageService.init();
    await CurrencyService.init();
    await ManualPriceService.init();
    await OnlineSettingsService.init();
    await OnlinePriceService.init();
    await SectorService.init();
    await AppearanceService.init();
    await CbrService.init();

    await StorageService.replaceFinancialData(deposits: const [], purchases: const [], incomes: const [], plans: const []);
    final start = DateTime.now().subtract(const Duration(days: 300));
    await StorageService.addPurchase(Purchase(
      id: 'sber',
      date: start,
      ticker: 'SBER',
      name: 'Сбербанк',
      type: AssetType.stock,
      quantity: 100,
      pricePerUnit: 250,
    ));
    await StorageService.addPurchase(Purchase(
      id: 'ofz',
      date: start.add(const Duration(days: 40)),
      ticker: 'SU26238RMFS4',
      name: 'ОФЗ 26238',
      type: AssetType.bond,
      quantity: 20,
      pricePerUnit: 700,
    ));
    await CbrService.saveMonths([
      for (int i = 0; i < 24; i++)
        CbrMonth(
          year: DateTime.now().year - 2 + (DateTime.now().month + i - 1) ~/ 12,
          month: (DateTime.now().month + i - 1) % 12 + 1,
          keyRate: 16,
          inflation: 7,
        ),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  /// Узкий телефон: 320 точек в ширину.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget Function(BuildContext) openButton) => MaterialApp(
        theme: AppTheme.build(Colors.blue, Brightness.dark),
        home: Scaffold(body: Center(child: Builder(builder: openButton))),
      );

  testWidgets('карточки-итоги помещаются на узком экране', (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Colors.blue, Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ChoiceCards(
            selected: 0,
            onSelect: (_) {},
            items: const [
              ChoiceCard(label: 'Выплаты', value: '~58 673 ₽', sub: 'за 12 месяцев', color: Colors.purple, money: true),
              ChoiceCard(
                label: 'Стоимость',
                value: '~2 858 291 ₽',
                sub: 'через 3 года · средний сценарий',
                color: Colors.blue,
                money: true,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Выплаты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('стресс-тест: первый экран, сценарий и разбор по бумагам', (tester) async {
    phone(tester);
    await tester.pumpWidget(app((context) => ElevatedButton(
          onPressed: () => showStressTestSheet(context),
          child: const Text('открыть'),
        )));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Стресс-тест'), findsOneWidget);
    expect(find.text('ОТКУДА ИЗМЕНЕНИЕ'), findsOneWidget);

    await tester.ensureVisible(find.text('Кризис'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кризис'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Разбор по всем бумагам ›'));
    await tester.tap(find.text('Разбор по всем бумагам ›'));
    await tester.pumpAndSettle();
    expect(find.textContaining('все бумаги'), findsOneWidget);
    expect(find.text('Сбербанк'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Против инфляции»: оба режима строятся', (tester) async {
    phone(tester);
    expect(AnalyticsService.currentHoldings(), isNotEmpty);
    await tester.pumpWidget(app((context) => ElevatedButton(
          onPressed: () => showRealReturnSheet(context, PeriodFilter.all),
          child: const Text('открыть'),
        )));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Против инфляции'), findsOneWidget);
    expect(find.text('С начала периода'), findsOneWidget);

    await tester.tap(find.text('В годовых'));
    await tester.pumpAndSettle();
    expect(find.text('Ключевая ставка'), findsOneWidget);

    await tester.tap(find.text('Год'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
