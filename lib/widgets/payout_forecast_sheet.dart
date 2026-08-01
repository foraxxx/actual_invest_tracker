import 'package:flutter/material.dart';

import '../design/charts.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_forecast_service.dart';

/// Единое окно прогноза выплат для всех экранов приложения.
void showPayoutForecastSheet(BuildContext context) {
  final byMonth = PayoutForecastService.portfolioForecastByMonth();
  final total = byMonth.values.fold(0.0, (sum, value) => sum + value);

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
              subtitle: 'Дивиденды и купоны на 12 месяцев со следующего месяца',
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    title: 'Ожидаемые выплаты по месяцам',
                    subtitle: 'Всего около ${Fmt.money(total)}',
                  ),
                  BarsChart(
                    values: byMonth.values.toList(),
                    labels: byMonth.keys.map(Fmt.monthKeyLabel).toList(),
                    color: AppColors.violet,
                    valueFormatter: Fmt.money,
                    height: 190,
                  ),
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
        ),
      ),
    ),
  );
}
