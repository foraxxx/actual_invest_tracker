import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invest_tracker/services/beta_service.dart';
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

  test('ключевая ставка по месяцам и средняя за период', () async {
    await CbrService.saveMonths(const [
      CbrMonth(year: 2025, month: 1, keyRate: 20, inflation: 9),
      CbrMonth(year: 2025, month: 2, keyRate: 10, inflation: 8),
    ]);
    expect(CbrService.keyRateAt(DateTime(2025, 1, 15)), 20);
    expect(CbrService.keyRateAt(DateTime(2025, 6, 1)), 10);
    expect(CbrService.inflationIn(DateTime(2025, 2, 10)), 8);
    expect(CbrService.inflationIn(DateTime(2025, 3, 10)), isNull);
    final avg = CbrService.averageKeyRate(DateTime(2025, 1, 1), DateTime(2025, 3, 1))!;
    expect(avg, closeTo((20 * 31 + 10 * 28) / 59, 0.01));
  });

  test('доходность по Дитцу не считает пополнение доходом', () {
    final r = RealReturnService.dietz(
      from: DateTime(2025, 1, 1),
      to: DateTime(2026, 1, 1),
      startValue: 100000,
      endValue: 160000,
      flows: [(DateTime(2026, 1, 1), 50000)],
    )!;
    expect(r, closeTo(0.10, 1e-9));
  });

  test('пополнение в середине года весит половину', () {
    final r = RealReturnService.dietz(
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 12, 31),
      startValue: 0,
      endValue: 110000,
      flows: [(DateTime(2025, 1, 1), 50000), (DateTime(2025, 7, 2), 50000)],
    )!;
    expect(r, closeTo(10000 / 75000, 0.01));
  });

  test('без своих денег доходности нет', () {
    final r = RealReturnService.dietz(
      from: DateTime(2025, 1, 1),
      to: DateTime(2026, 1, 1),
      startValue: 0,
      endValue: 0,
      flows: const [],
    );
    expect(r, isNull);
  });

  test('бета по недельным ценам', () {
    final start = DateTime(2024, 1, 1);
    final index = <MapEntry<DateTime, double>>[];
    final stock = <MapEntry<DateTime, double>>[];
    var i = 1000.0;
    var s = 100.0;
    for (int k = 0; k < 60; k++) {
      final d = start.add(Duration(days: 7 * k));
      final move = (k % 3 == 0 ? 0.02 : -0.01) + (k % 5 == 0 ? 0.015 : 0);
      i *= 1 + move;
      s *= 1 + 1.5 * move;
      index.add(MapEntry(d, i));
      stock.add(MapEntry(d, s));
    }
    expect(BetaService.estimate(stock, index), closeTo(1.5, 0.05));
    expect(BetaService.estimate(stock.take(10).toList(), index), isNull);
  });

  test('рубль −20% — доллар +25%', () {
    const s = StressScenario(id: 'x', title: 'x', caption: 'x', ruble: -20);
    expect(s.fx, closeTo(0.25, 1e-9));
    const crisis = StressScenario(id: 'c', title: 'c', caption: 'c', market: -25, rate: 3);
    expect(StressTestService.indexChange(crisis), closeTo(-37, 1e-9));
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
