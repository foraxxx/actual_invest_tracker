import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/tokens.dart';
import '../services/payout_calendar_service.dart';
import 'month_calendar.dart';

/// Календарь выплат: 12 месяцев, прогноз обведён пунктиром. Нажатие на месяц
/// показывает каждую выплату — дату, название бумаги и сумму; ожидаемые
/// выплаты серым и с «≈».
class PayoutCalendar extends StatelessWidget {
  final List<PayoutMonthCell> cells;

  const PayoutCalendar({super.key, required this.cells});

  /// Клетки календаря выплат в общем виде [MonthCalendar].
  static List<CalendarMonth> toMonths(List<PayoutMonthCell> cells) => [
        for (final c in cells)
          CalendarMonth(
            month: c.month,
            value: c.total,
            main: c.isEmpty ? '—' : '${c.hasForecast ? '≈' : ''}${Fmt.money(c.total)}',
            forecast: c.hasForecast,
            onlyForecast: c.hasForecast && c.received <= 0,
            summary: _summary(c),
            lines: [
              for (final i in c.items)
                CalendarLine(
                  date: i.date,
                  title: PayoutCalendarService.nameOf(i.ticker),
                  amount: '${i.expected ? '≈' : ''}${Fmt.money(i.rub)}',
                  muted: i.expected,
                  ticker: i.ticker,
                ),
            ],
          ),
      ];

  static String _summary(PayoutMonthCell c) {
    final parts = <String>[
      if (c.receivedCount > 0) '${c.receivedCount} ${Fmt.payouts(c.receivedCount)}',
      if (c.hasForecast && c.received > 0) 'ещё ожидается',
      if (c.hasForecast && c.received <= 0) 'ожидается',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return MonthCalendar(months: toMonths(cells), color: AppColors.positive);
  }
}
