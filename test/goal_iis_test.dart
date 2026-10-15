import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/goal_service.dart';
import 'package:invest_tracker/services/iis_service.dart';

/// Расчёт взноса для финансовой цели и сроки ИИС.
void main() {
  group('requiredMonthly', () {
    test('без роста — просто делим недостающее на месяцы', () {
      expect(GoalService.requiredMonthly(current: 100, target: 1300, months: 12, rate: 0), closeTo(100, 1e-9));
    });

    test('с ростом взнос меньше, и цель достигается точно к сроку', () {
      const rate = 0.01;
      const months = 24;
      final pmt = GoalService.requiredMonthly(current: 1000, target: 5000, months: months, rate: rate);
      expect(pmt, lessThan((5000 - 1000) / months));
      var v = 1000.0;
      for (int i = 0; i < months; i++) {
        v = v * (1 + rate) + pmt;
      }
      expect(v, closeTo(5000, 1e-6));
    });

    test('если рост и так довезёт до цели — взнос не нужен', () {
      final grown = 1000 * math.pow(1.02, 36);
      expect(GoalService.requiredMonthly(current: 1000, target: grown - 1, months: 36, rate: 0.02), 0);
    });

    test('срок наступил — нужна вся разница', () {
      expect(GoalService.requiredMonthly(current: 700, target: 1000, months: 0, rate: 0.01), 300);
    });
  });

  group('ИИС: минимальный срок', () {
    IisSettings s(IisType t, int year) => IisSettings(type: t, openedAt: DateTime(year, 3, 12));

    test('новый ИИС: 5 лет для 2024–2026, дальше на год больше, не больше 10', () {
      expect(IisService.minTermYears(s(IisType.newType, 2024)), 5);
      expect(IisService.minTermYears(s(IisType.newType, 2026)), 5);
      expect(IisService.minTermYears(s(IisType.newType, 2027)), 6);
      expect(IisService.minTermYears(s(IisType.newType, 2031)), 10);
      expect(IisService.minTermYears(s(IisType.newType, 2040)), 10);
    });

    test('старый ИИС — 3 года', () {
      expect(IisService.minTermYears(s(IisType.oldA, 2022)), 3);
      expect(IisService.minTermYears(s(IisType.oldB, 2023)), 3);
    });

    test('дата окончания срока', () {
      expect(IisService.minTermEnd(s(IisType.newType, 2025)), DateTime(2030, 3, 12));
    });
  });
}
