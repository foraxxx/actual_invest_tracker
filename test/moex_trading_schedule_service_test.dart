import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/moex_trading_schedule_service.dart';

void main() {
  group('MoexTradingScheduleService', () {
    test('opens and closes by Moscow time', () {
      // 3 August 2026 is Monday. Moscow is UTC+3.
      expect(
        MoexTradingScheduleService.isTradingSession(DateTime.utc(2026, 8, 3, 3, 49)),
        isFalse,
      );
      expect(
        MoexTradingScheduleService.isTradingSession(DateTime.utc(2026, 8, 3, 3, 50)),
        isTrue,
      );
      expect(
        MoexTradingScheduleService.isTradingSession(DateTime.utc(2026, 8, 3, 20, 50)),
        isFalse,
      );
    });

    test('does not open on weekends', () {
      expect(
        MoexTradingScheduleService.isTradingSession(DateTime.utc(2026, 8, 1, 9)),
        isFalse,
      );
    });

    test('requests one delayed final refresh after a trading day', () {
      final now = DateTime.utc(2026, 8, 3, 21, 5); // 00:05 MSK on Tuesday.
      final beforeClose = DateTime.utc(2026, 8, 3, 20, 49);
      expect(MoexTradingScheduleService.needsFinalRefresh(beforeClose, now), isTrue);
      expect(MoexTradingScheduleService.needsFinalRefresh(now, now), isFalse);
    });

    test('sleeps until Monday after the Friday final refresh', () {
      final saturday = DateTime.utc(2026, 8, 7, 21, 10); // Saturday 00:10 MSK.
      final delay = MoexTradingScheduleService.nextAutomaticDelay(60, saturday);
      expect(delay, const Duration(days: 2, hours: 6, minutes: 40));
    });

    test('wakes once after the evening session for delayed final prices', () {
      final fridayEvening = DateTime.utc(2026, 8, 7, 20, 55); // Friday 23:55 MSK.
      final delay = MoexTradingScheduleService.nextAutomaticDelay(60, fridayEvening);
      expect(delay, const Duration(minutes: 10));
    });
  });
}
