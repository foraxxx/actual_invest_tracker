import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/services/cbr_service.dart';
import 'package:invest_tracker/services/real_return_service.dart';
import 'package:invest_tracker/services/stress_test_service.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('invest_tracker_cbr_test_');
    Hive.init(hiveDir.path);
    await CbrService.init();
  });

  Future<void> flat({double key = 10, double infl = 10}) => CbrService.saveMonths([
        for (int y = 2020; y <= 2026; y++)
          for (int m = 1; m <= 12; m++) CbrMonth(year: y, month: m, keyRate: key, inflation: infl),
      ]);

  test('разбор таблицы Банка России', () {
    const html = '''
<html><body>
<table class="data">
  <tr><th>Дата</th><th>Ключевая ставка, % годовых</th><th>Инфляция, % г/г</th><th>Цель по инфляции, %</th></tr>
  <tr><td>09.2026</td><td>16,00</td><td>6,50</td><td>4,00</td></tr>
  <tr><td>08.2026</td><td>17,00</td><td>7,10</td><td>4,00</td></tr>
  <tr><td>07.2026</td><td>18,00</td><td>&nbsp;</td><td>4,00</td></tr>
</table>
</body></html>''';
    final months = CbrService.parse(Uint8List.fromList(utf8.encode(html)));
    expect(months, hasLength(3));
    expect(months.first.year, 2026);
    expect(months.first.month, 9);
    expect(months.first.keyRate, 16);
    expect(months.first.inflation, 6.5);
    expect(months[1].inflation, closeTo(7.1, 1e-9));
    expect(months[2].inflation, isNull);
  });

  test('страница без таблицы — пустой список', () {
    final months = CbrService.parse(Uint8List.fromList(utf8.encode('<html>нет данных</html>')));
    expect(months, isEmpty);
  });

  test('рост цен и ключевая ставка за год', () async {
    await flat();
    final infl = CbrService.inflationFactor(DateTime(2025, 1, 1), DateTime(2026, 1, 1))!;
    expect(infl, closeTo(1.10, 0.002));
    final key = CbrService.keyRateFactor(DateTime(2025, 1, 1), DateTime(2026, 1, 1))!;
    expect(key, closeTo(1.10, 0.002));
    expect(CbrService.lastInflation!.year, 2026);
  });

  test('месяцы без данных берут последнее известное значение', () async {
    await CbrService.saveMonths(const [
      CbrMonth(year: 2025, month: 1, keyRate: 20, inflation: 10),
    ]);
    final f = CbrService.inflationFactor(DateTime(2026, 1, 1), DateTime(2027, 1, 1))!;
    expect(f, closeTo(1.10, 0.002));
  });

  test('портфель против инфляции', () async {
    await flat(key: 15, infl: 10);
    final r = RealReturnService.compute(
      from: DateTime(2025, 1, 1),
      to: DateTime(2026, 1, 1),
      startAccount: 0,
      flows: [(DateTime(2025, 1, 1), 100000)],
      endAccount: 120000,
    )!;
    expect(r.base, 100000);
    expect(r.portfolioPct, closeTo(20, 1e-6));
    expect(r.inflationPct, closeTo(10, 0.2));
    expect(r.keyRatePct, closeTo(15, 0.2));
    expect(r.vsInflation, closeTo(10, 0.2));
    expect(r.vsKeyRate, closeTo(5, 0.2));
    expect(r.realGainRub, closeTo(10000, 200));
  });

  test('пополнение посреди периода растёт только со своего дня', () async {
    await flat(key: 10, infl: 10);
    final r = RealReturnService.compute(
      from: DateTime(2025, 1, 1),
      to: DateTime(2026, 1, 1),
      startAccount: 100000,
      flows: [(DateTime(2026, 1, 1), 50000)],
      endAccount: 160000,
    )!;
    expect(r.base, 150000);
    expect(r.inflation, closeTo(160000, 300));
  });

  test('без своих денег сравнивать не с чем', () async {
    await flat();
    final r = RealReturnService.compute(
      from: DateTime(2025, 1, 1),
      to: DateTime(2026, 1, 1),
      startAccount: 0,
      flows: const [],
      endAccount: 0,
    );
    expect(r, isNull);
  });

  test('дюрация облигации', () {
    expect(StressTestService.bondDuration(yieldPct: 14, years: 0), 0);
    expect(StressTestService.bondDuration(yieldPct: 0, years: 3), 3);
    expect(StressTestService.bondDuration(yieldPct: 10, years: 1), closeTo(0.909, 0.001));
    final long = StressTestService.bondDuration(yieldPct: 14, years: 10);
    expect(long, greaterThan(4.5));
    expect(long, lessThan(10));
  });
}
