import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/services/backup_service.dart';
import 'package:invest_tracker/services/currency_service.dart';
import 'package:invest_tracker/services/goal_service.dart';
import 'package:invest_tracker/services/iis_service.dart';
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
    await GoalService.init();
    await IisService.init();
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

  group('общий бэкап всех портфелей', () {
    String fullBackup(List<Map<String, dynamic>> purchases) => jsonEncode({
          'version': 5,
          'exportedAt': DateTime(2026, 10, 1).toIso8601String(),
          'portfolios': [
            {
              'name': 'Тестовый ИИС',
              'status': 'active',
              'purchases': purchases,
              'customSectors': ['Мой сектор'],
              'sectorAssignments': {'SU26228RMFS5': 'Мой сектор'},
              'iis': {'t': 'newType', 'o': '2025-01-10T00:00:00.000', 'r': 13},
              'goal': {'a': 1000000, 'y': 2030, 'm': 11, 's': 20000},
            },
          ],
        });

    PortfolioMeta portfolioNamed(String name) => PortfolioService.list.singleWhere((p) => p.name == name);

    test('недостающий портфель создаётся, активный не меняется', () async {
      final activeBefore = PortfolioService.activeId;
      final result = await BackupService.importFromJson(fullBackup([
        {...bondSale(fee: 10), 'id': 'buy-iis', 'isSell': false},
      ]));

      expect(result.portfolios, 1);
      expect(PortfolioService.activeId, activeBefore);
      final meta = portfolioNamed('Тестовый ИИС');
      final records = await StorageService.readAllFor(meta.id);
      expect(records.purchases.single.id, 'buy-iis');
      final sectors = await SectorService.readFor(meta.id);
      expect(sectors.custom, ['Мой сектор']);
      expect(IisService.settingsFor(meta.id)?.type, IisType.newType);
      expect(GoalService.goalFor(meta.id)?.monthlySaving, 20000);
      // В активный портфель ничего не попало.
      expect(StorageService.purchases, isEmpty);
    });

    test('портфель с тем же названием заменяется, а не дублируется', () async {
      await BackupService.importFromJson(fullBackup([
        {...bondSale(fee: 10), 'id': 'buy-1', 'isSell': false},
      ]));
      await BackupService.importFromJson(fullBackup([
        {...bondSale(fee: 10), 'id': 'buy-2', 'isSell': false},
      ]));

      final meta = portfolioNamed('Тестовый ИИС');
      final records = await StorageService.readAllFor(meta.id);
      expect(records.purchases.map((p) => p.id), ['buy-2']);
    });
  });
}
