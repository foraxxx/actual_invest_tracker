import 'package:flutter/material.dart';

import '../design/format.dart';
import '../services/analytics_service.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_calendar_service.dart';
import '../services/payout_forecast_service.dart';
import 'payout_calendar.dart';

const payoutForecastSubtitle = 'Прогноз выплат на следующие 12 месяцев';

/// Сумма ожидаемых выплат за 12 месяцев.
double payoutForecastTotal() =>
    PayoutForecastService.portfolioForecastByMonth().values.fold(0.0, (sum, value) => sum + value);

/// Окно прогноза выплат — для экранов, где переключаться на прогноз
/// стоимости не нужно. На главной открывается общее окно «Прогноз».
void showPayoutForecastSheet(BuildContext context) {
  showAppSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'Прогноз выплат',
              subtitle: payoutForecastSubtitle,
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 16),
            const PayoutForecastBody(),
          ],
        ),
      ),
    ),
  );
}

const payoutForecastInfo = 'Месяцы — по объявленному графику выплат, а если его ещё нет — '
    'по исторической сезонности. Суммы после налога. Это прогноз, а не гарантия.';

/// Содержимое прогноза выплат: сумма за 12 месяцев и календарь.
class PayoutForecastBody extends StatelessWidget {
  const PayoutForecastBody({super.key});

  @override
  Widget build(BuildContext context) {
    final total = payoutForecastTotal();
    final value = AnalyticsService.currentPortfolioValueRub();
    final yieldPct = value > 0 ? total / value * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            Text('≈ ${Fmt.money(total)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.positive)),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('за 12 мес${yieldPct > 0 ? ' · ${Fmt.pct(yieldPct).replaceAll('+', '')}' : ''}',
                  style: TextStyle(fontSize: 13, color: context.dim)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Нажатие на месяц показывает, от каких бумаг ждать деньги.
        PayoutCalendar(cells: PayoutCalendarService.next12()),
      ],
    );
  }
}
