import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/widgets/updated_ago.dart';

/// Подпись «обновлено … назад» у котировок.
void main() {
  final now = DateTime(2026, 10, 13, 15, 30);

  test('недавно', () {
    expect(UpdatedAgo.label(now.subtract(const Duration(seconds: 20)), now), 'обновлено только что');
    expect(UpdatedAgo.label(now.subtract(const Duration(minutes: 7)), now), 'обновлено 7 мин назад');
  });

  test('давно', () {
    expect(UpdatedAgo.label(DateTime(2026, 10, 13, 9, 5), now), 'обновлено в 09:05');
    expect(UpdatedAgo.label(DateTime(2026, 10, 12, 18, 45), now), 'обновлено вчера в 18:45');
    expect(UpdatedAgo.label(DateTime(2026, 10, 1, 10, 0), now), 'обновлено 01.10 в 10:00');
    expect(UpdatedAgo.label(null, now), 'ещё не обновлялось');
  });
}
