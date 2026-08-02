import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/design/charts.dart';

void main() {
  group('chartWindowForDates', () {
    test('year starts at the same calendar date, not at one fifth of points', () {
      final dates = <DateTime>[
        DateTime(2024, 1, 10),
        DateTime(2025, 7, 31),
        DateTime(2025, 8, 2),
        DateTime(2026, 8, 2),
      ];

      final window = chartWindowForDates(dates, ChartRange.year);

      expect(window.start, 2);
      expect(window.size, 2);
    });

    test('month clamps the day for a shorter calendar month', () {
      expect(
        ChartRange.month.windowFrom(DateTime(2026, 3, 31)),
        DateTime(2026, 2, 28),
      );
    });

    test('all range keeps the complete loaded history', () {
      final dates = [DateTime(2001), DateTime(2010), DateTime(2026)];

      final window = chartWindowForDates(dates, ChartRange.all);

      expect(window.start, 0);
      expect(window.size, dates.length);
    });
  });
}
