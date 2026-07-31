import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/financial_math.dart';

void main() {
  group('XIRR', () {
    test('удвоение за 365 дней даёт 100%', () {
      final result = FinancialMath.xirrPercent([
        DatedCashFlow(DateTime(2024, 1, 1), -1000),
        DatedCashFlow(DateTime(2024, 12, 31), 2000),
      ]);
      expect(result, closeTo(100, 0.01));
    });

    test('учитывает дату дополнительного вложения', () {
      final result = FinancialMath.xirrPercent([
        DatedCashFlow(DateTime(2024, 1, 1), -1000),
        DatedCashFlow(DateTime(2024, 7, 1), -1000),
        DatedCashFlow(DateTime(2024, 12, 31), 2300),
      ]);
      expect(result, isNotNull);
      expect(result!, inInclusiveRange(0, 30));
    });

    test('требует потоки разных знаков', () {
      expect(
        FinancialMath.xirrPercent([
          DatedCashFlow(DateTime(2024), -100),
          DatedCashFlow(DateTime(2025), -50),
        ]),
        isNull,
      );
    });
  });

  group('TWR', () {
    test('исключает влияние пополнения', () {
      final result = FinancialMath.twrPercent(const [
        TwrPeriod(startValue: 100, endValue: 160, externalFlow: 50),
      ]);
      expect(result, closeTo(10, 1e-9));
    });

    test('геометрически связывает периоды', () {
      final result = FinancialMath.twrPercent(const [
        TwrPeriod(startValue: 100, endValue: 110),
        TwrPeriod(startValue: 110, endValue: 99),
      ]);
      expect(result, closeTo(-1, 1e-9));
    });
  });
}
