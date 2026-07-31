import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/models/purchase.dart';
import 'package:invest_tracker/services/analytics_service.dart';
import 'package:invest_tracker/services/annual_report_service.dart';
import 'package:invest_tracker/services/currency_service.dart';
import 'package:invest_tracker/services/manual_price_service.dart';
import 'package:invest_tracker/services/online_price_service.dart';
import 'package:invest_tracker/services/online_settings_service.dart';
import 'package:invest_tracker/services/portfolio_service.dart';
import 'package:invest_tracker/services/sector_service.dart';
import 'package:invest_tracker/services/storage_service.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_test_');
    Hive.init(hiveDir.path);
    StorageService.registerAdapters();
    await PortfolioService.init();
    await StorageService.init();
    await CurrencyService.init();
    await ManualPriceService.init();
    await OnlineSettingsService.init();
    await OnlinePriceService.init();
    await SectorService.init();
  });

  setUp(() async {
    await StorageService.replaceFinancialData(
      deposits: const [],
      purchases: const [],
      incomes: const [],
      plans: const [],
    );
    await ManualPriceService.clear('TEST');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  test('частичная продажа корректно делит реализованный и открытый P&L',
      () async {
    await StorageService.addPurchase(Purchase(
      id: 'buy',
      date: DateTime(2024, 1, 1),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 10,
      pricePerUnit: 100,
      fee: 10,
    ));
    await StorageService.addPurchase(Purchase(
      id: 'sell',
      date: DateTime(2024, 6, 1),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 4,
      pricePerUnit: 150,
      fee: 6,
      isSell: true,
    ));

    final holding = AnalyticsService.currentHoldings()['TEST']!;
    expect(holding.qty, 6);
    expect(holding.costBasisRub, closeTo(606, 1e-9));
    expect(holding.pnlRub, closeTo(294, 1e-9));
    expect(AnalyticsService.totalRealizedPnlRub(), closeTo(190, 1e-9));
    expect(AnalyticsService.totalInvested(), closeTo(416, 1e-9));
  });

  test('исторический срез не видит будущую продажу', () async {
    await StorageService.addPurchase(Purchase(
      id: 'buy',
      date: DateTime(2024, 1, 1),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 10,
      pricePerUnit: 100,
    ));
    await StorageService.addPurchase(Purchase(
      id: 'sell',
      date: DateTime(2025, 1, 1),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 10,
      pricePerUnit: 120,
      isSell: true,
    ));

    expect(
      AnalyticsService.holdingsAt(date: DateTime(2024, 12, 31))['TEST']!.qty,
      10,
    );
    expect(AnalyticsService.currentHoldings(), isEmpty);
  });

  test('годовой результат включает переоценку открытой позиции', () async {
    await StorageService.addPurchase(Purchase(
      id: 'buy',
      date: DateTime(2024, 1, 1),
      ticker: 'TEST',
      name: 'Test',
      type: AssetType.stock,
      quantity: 10,
      pricePerUnit: 100,
    ));
    await ManualPriceService.setAt('TEST', DateTime(2024, 12, 31), 120);

    final report = AnnualReportService.build(2024);
    expect(report.valueEndRub, 1200);
    expect(report.totalResultRub, 200);
  });
}
