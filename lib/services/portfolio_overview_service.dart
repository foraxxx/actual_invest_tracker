import 'portfolio_service.dart';
import 'storage_service.dart';
import 'analytics_service.dart';

/// Сводные показатели одного портфеля — для экрана "Все портфели".
class PortfolioSummary {
  final PortfolioMeta meta;
  final double valueRub;
  final double profitRub;
  final int holdingsCount;

  const PortfolioSummary({
    required this.meta,
    required this.valueRub,
    required this.profitRub,
    required this.holdingsCount,
  });
}

/// Считает сводку по каждому портфелю сразу, не переключая активный —
/// для неактивных портфелей их данные читаются во временно открытых
/// (и сразу закрытых) боксах через StorageService.readSnapshot.
class PortfolioOverviewService {
  static Future<List<PortfolioSummary>> allSummaries() async {
    final result = <PortfolioSummary>[];
    for (final meta in PortfolioService.list) {
      final snap = await StorageService.readSnapshot(meta.id);
      final holdings = AnalyticsService.currentHoldings(purchasesOverride: snap.purchases);
      final valueRub = holdings.values.fold(0.0, (s, h) => s + h.valueRub);
      final unrealized = holdings.values.fold(0.0, (s, h) => s + h.pnlRub);
      final realized = AnalyticsService.totalRealizedPnlRub(purchasesOverride: snap.purchases);
      final income = AnalyticsService.totalIncome(incomesOverride: snap.incomes);
      result.add(PortfolioSummary(
        meta: meta,
        valueRub: valueRub,
        profitRub: unrealized + realized + income,
        holdingsCount: holdings.length,
      ));
    }
    return result;
  }
}
