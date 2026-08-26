import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/services/backup_service.dart';
import 'package:invest_tracker/services/currency_service.dart';
import 'package:invest_tracker/services/manual_price_service.dart';
import 'package:invest_tracker/services/online_price_service.dart';
import 'package:invest_tracker/services/online_settings_service.dart';
import 'package:invest_tracker/services/portfolio_service.dart';
import 'package:invest_tracker/services/sector_service.dart';
import 'package:invest_tracker/services/storage_service.dart';

/// Импорт бэкапа должен принимать то, что записал экспорт.
///
/// Проверяется случай, на котором это правило было нарушено: продажа
/// облигации, где полученный НКД больше комиссий. Комиссия в модели — это
/// поправка к сумме сделки (при продаже считается `qty * price - fee`),
/// поэтому там законно оказывается отрицательное число. Экспорт его сохранял,
/// а импорт объявлял такой файл повреждённым и отказывался читать бэкап
/// целиком — одна сделка блокировала восстановление всех данных.
///
/// JSON собирается вручную, а не через экспорт: так тест не тянет за собой
/// шеринг файла, шифрование и настройки оформления.
void main() {
  late Directory hiveDir;

  String backupWith(List<Map<String, dynamic>> purchases) => jsonEncode({
        'version': 4,
        'exportedAt': DateTime(2026, 1, 27).toIso8601String(),
        'purchases': purchases,
      });

  Map<String, dynamic> bondSale({required double fee}) => {
        'id': 'sale-1',
        'date': DateTime(2026, 1, 27).toIso8601String(),
        'ticker': 'SU26228RMFS5',
        'name': 'ОФЗ-ПД 26228 10/04/30',
        'type': 1,
        'quantity': 33.0,
        'pricePerUnit': 795.49,
        'fee': fee,
        'currency': 'RUB',
        'note': 'Импорт из отчёта брокера',
        'sector': '',
        'isSell': true,
        'planId': null,
      };

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_backup_test_');
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
  });

  test('продажа облигации с отрицательной комиссией импортируется', () async {
    await BackupService.importFromJson(backupWith([bondSale(fee: -710.97)]));

    final restored = StorageService.purchases;
    expect(restored, hasLength(1));
    expect(restored.single.ticker, 'SU26228RMFS5');
    expect(restored.single.fee, closeTo(-710.97, 0.001));
    expect(restored.single.isSell, isTrue);
  });

  test('обычная покупка с положительной комиссией не сломана', () async {
    await BackupService.importFromJson(backupWith([
      {...bondSale(fee: 13454.69), 'id': 'buy-1', 'isSell': false},
    ]));

    expect(StorageService.purchases.single.fee, closeTo(13454.69, 0.001));
  });

  test('нулевое количество по-прежнему отвергается', () async {
    expect(
      () => BackupService.importFromJson(backupWith([
        {...bondSale(fee: 0), 'quantity': 0.0},
      ])),
      throwsA(isA<FormatException>()),
    );
  });

  test('отрицательная цена по-прежнему отвергается', () async {
    expect(
      () => BackupService.importFromJson(backupWith([
        {...bondSale(fee: 0), 'pricePerUnit': -1.0},
      ])),
      throwsA(isA<FormatException>()),
    );
  });
}
