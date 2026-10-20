import 'package:flutter/material.dart';

import '../design/format.dart';
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

/// Содержимое прогноза выплат: календарь на 12 месяцев и пояснение.
class PayoutForecastBody extends StatelessWidget {
  const PayoutForecastBody({super.key});

  @override
  Widget build(BuildContext context) {
    final total = payoutForecastTotal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: 'Ожидаемые выплаты по месяцам',
                subtitle: 'Всего около ${Fmt.money(total)}',
              ),
              // Все клетки — прогноз, поэтому пунктирные. Нажатие на месяц
              // показывает, от каких бумаг ждать деньги.
              PayoutCalendar(cells: PayoutCalendarService.next12()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          icon: Icons.info_outline_rounded,
          color: AppColors.info,
          text: 'Месяцы определяются по объявленному графику выплат, а '
              'если его ещё нет — по исторической сезонности. Прогноз не '
              'является гарантией будущих выплат.',
        ),
      ],
    );
  }
}
