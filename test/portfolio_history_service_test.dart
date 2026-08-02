import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/portfolio_history_service.dart';

void main() {
  test('current graph point always uses the current portfolio value', () {
    final today = DateTime(2026, 8, 2, 14, 30);
    final source = <MapEntry<DateTime, double>>[
      MapEntry(DateTime(2026, 8, 1), 900000),
      MapEntry(DateTime(2026, 8, 2, 9), 950000),
    ];

    final result = PortfolioHistoryService.withCurrentPoint(
      source,
      1234567890,
      now: today,
    );

    expect(result, hasLength(2));
    expect(result.last.key, today);
    expect(result.last.value, 1234567890);
  });
}
