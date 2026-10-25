import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/home_widget_config.dart';
import 'package:invest_tracker/services/work_calendar.dart';

void main() {
  group('день выплаты — ближайший рабочий день месяца', () {
    test('суббота — пятница', () {
      expect(WorkCalendar.payDay(DateTime(2026, 10, 31)), DateTime(2026, 10, 30));
    });

    test('воскресенье — понедельник', () {
      expect(WorkCalendar.payDay(DateTime(2026, 11, 15)), DateTime(2026, 11, 16));
    });

    test('последний день месяца в воскресенье — пятница', () {
      expect(WorkCalendar.payDay(DateTime(2026, 5, 31)), DateTime(2026, 5, 29));
    });

    test('рабочий день не меняется', () {
      expect(WorkCalendar.payDay(DateTime(2026, 10, 15)), DateTime(2026, 10, 15));
    });

    test('праздник в выходной — свободен понедельник', () {
      // 8 марта 2026 — воскресенье, 9-е выходной: ближайший рабочий — 10-е.
      expect(WorkCalendar.isWorkDay(DateTime(2026, 3, 9)), isFalse);
      expect(WorkCalendar.payDay(DateTime(2026, 3, 9)), DateTime(2026, 3, 10));
      // 9 мая 2026 — суббота, 11-е выходной: ближайший рабочий — 12-е.
      expect(WorkCalendar.isWorkDay(DateTime(2026, 5, 11)), isFalse);
      expect(WorkCalendar.payDay(DateTime(2026, 5, 11)), DateTime(2026, 5, 12));
    });

    test('праздники', () {
      expect(WorkCalendar.isWorkDay(DateTime(2026, 6, 12)), isFalse);
      expect(WorkCalendar.isWorkDay(DateTime(2026, 11, 4)), isFalse);
      expect(WorkCalendar.isWorkDay(DateTime(2026, 2, 23)), isFalse);
    });

    test('в прошлый месяц не уходит — тогда ближайший рабочий после', () {
      expect(WorkCalendar.payDay(DateTime(2026, 1, 5)), DateTime(2026, 1, 9));
    });
  });

  group('настройки виджета', () {
    test('сохраняются и читаются без потерь', () {
      final c = WidgetConfig.defaults('all')
          .withSource('p1')
          .withStyle(const WidgetStyle().copyWith(bg: 0x123456, bgAlpha: 70, border: 'edge', shadow: 'soft'))
          .withSize(
            WidgetSize.s22,
            WidgetSizeConfig.defaults(WidgetSize.s22).copyWith(slot: WidgetSlot.leaders, fit: true, width: 85, align: 'top'),
          );
      final back = WidgetConfig.decode(c.encode(), 'all');
      expect(back.source, 'p1');
      expect(back.style.bg, 0x123456);
      expect(back.style.bgAlpha, 70);
      expect(back.style.border, 'edge');
      expect(back.style.shadow, 'soft');
      expect(back.style.preset, 'custom');
      final s = back.of(WidgetSize.s22);
      expect(s.slot, WidgetSlot.leaders);
      expect(s.fit, isTrue);
      expect(s.width, 85);
      expect(s.align, 'top');
      expect(back.of(WidgetSize.s32).slot, WidgetSlot.chartBudget);
    });

    test('неподходящее содержимое для размера заменяется своим по умолчанию', () {
      final raw = '{"src":"all","sz":{"s42":{"sl":"chartBudget","w":10}}}';
      final c = WidgetConfig.decode(raw, 'all');
      expect(c.of(WidgetSize.s42).slot, WidgetSlot.budget);
      expect(c.of(WidgetSize.s42).width, 60);
    });

    test('испорченная запись — настройки по умолчанию', () {
      final c = WidgetConfig.decode('{не json', 'x');
      expect(c.source, 'x');
      expect(c.of(WidgetSize.s22).slot, WidgetSlot.chart);
    });
  });
}
