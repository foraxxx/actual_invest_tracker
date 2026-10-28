import 'package:flutter/material.dart';

import '../design/format.dart';
import '../services/analytics_service.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_calendar_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/tax_service.dart';
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

List<(String, String)> payoutForecastInfo() {
  final rate = (PayoutForecastService.netFactor < 1) ? '${((1 - PayoutForecastService.netFactor) * 100).round()}%' : null;
  return [
    ('Суммы', rate == null
        ? 'как их объявляет компания.'
        : 'дивиденды — уже за вычетом налога $rate, столько придёт на счёт. Купоны — целиком, '
            'с них налог при выплате не удерживается.'),
    ('Когда придут', 'если компания объявила дату — по ней. Если нет — в тот месяц, в который она обычно платила раньше.'),
    ('Сколько', 'объявленные выплаты и прогноз по каждой бумаге, умноженные на то количество, что у вас сейчас.'),
    ('Налог с дивидендов', 'ставка берётся из настроек счёта: для ИИС — та, что указана у счёта, '
        'иначе — из настроек налога (13% или 15%).'),
  ];
}

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
              child: Text(
                  'за 12 мес${yieldPct > 0 ? ' · ${Fmt.pct(yieldPct).replaceAll('+', '')}' : ''}'
                  '${PayoutForecastService.netFactor < 1 ? ' · дивиденды после налога ${((1 - PayoutForecastService.netFactor) * 100).round()}%' : ''}',
                  style: TextStyle(fontSize: 13, color: context.dim)),
            ),
          ],
        ),
        _couponTax(context, total),
        const SizedBox(height: 12),
        // Нажатие на месяц показывает, от каких бумаг ждать деньги.
        PayoutCalendar(cells: PayoutCalendarService.next12()),
      ],
    );
  }
}


/// Налог с купонов на обычном брокерском счёте: купоны приходят целиком,
/// а налог брокер спишет потом.
Widget _couponTax(BuildContext context, double total) {
  if (TaxService.regime != TaxRegime.regular) return const SizedBox.shrink();
  final coupons = PayoutForecastService.couponForecastTotal();
  if (coupons <= 0.5) return const SizedBox.shrink();
  final tax = coupons * TaxService.rate;
  Widget row(String title, String value, {String? sub, Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 11, height: 1.3, color: context.dim)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Купоны придут целиком', Fmt.money(coupons)),
        row('Налог с купонов за год', '≈ −${Fmt.money(tax)}',
            sub: 'брокер спишет со счёта, если там будут свободные рубли; если нет — придёт уведомление из налоговой',
            color: AppColors.negative),
        row('После налога', '≈ ${Fmt.money(total - tax)}', color: AppColors.positive),
      ],
    ),
  );
}
