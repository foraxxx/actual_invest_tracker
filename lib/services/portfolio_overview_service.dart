import 'portfolio_service.dart';
import 'storage_service.dart';
import 'analytics_service.dart';
import '../models/purchase.dart';

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
/// (и сразу закрытых) боксах через StorageService.readDataFor.
class PortfolioOverviewService {
  static Future<List<PortfolioSummary>> allSummaries() async {
    final result = <PortfolioSummary>[];
    for (final meta in PortfolioService.list) {
      final snap = await StorageService.readDataFor(meta.id);
      final summary = AnalyticsService.summaryFor(
        purchases: snap.purchases,
        incomes: snap.incomes,
      );
      final holdingsCount = _holdingCount(snap.purchases);
      result.add(PortfolioSummary(
        meta: meta,
        valueRub: summary.valueRub,
        profitRub: summary.profitRub,
        holdingsCount: holdingsCount,
      ));
    }
    return result;
  }

  static int _holdingCount(List<Purchase> purchases) {
    final quantities = <String, double>{};
    for (final purchase in purchases) {
      final current = quantities[purchase.ticker] ?? 0;
      quantities[purchase.ticker] =
          current + (purchase.isSell ? -purchase.quantity : purchase.quantity);
    }
    return quantities.values.where((quantity) => quantity > 1e-9).length;
  }
}
