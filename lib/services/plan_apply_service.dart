import '../models/plan.dart';
import 'storage_service.dart';

/// Засчитывание покупки в план.
///
/// Логика одна для формы сделки и для быстрой покупки из карточки бумаги,
/// поэтому живёт отдельно, а не внутри экрана.
class PlanApplyService {
  PlanApplyService._();

  /// Есть ли активный план по этой бумаге на текущий месяц — от этого зависит,
  /// показывать ли галку «учитывать в плане».
  static bool hasPlanThisMonth(String ticker) => _candidates(ticker).isNotEmpty;

  static List<Plan> _candidates(String ticker) {
    final now = DateTime.now();
    return StorageService.plans
        .where((p) =>
            p.ticker.toUpperCase() == ticker.toUpperCase() &&
            p.status == PlanStatus.active &&
            p.targetDate != null &&
            p.targetDate!.year == now.year &&
            p.targetDate!.month == now.month)
        .toList();
  }

  /// Добавляет купленное к ближайшему по дате плану этого месяца и пересчитывает
  /// среднюю цену покупки по плану.
  static Future<void> applyToNearestPlanThisMonth(String ticker, double qty, double price) async {
    final candidates = _candidates(ticker);
    if (candidates.isEmpty) return;

    final now = DateTime.now();
    candidates.sort((a, b) =>
        (a.targetDate!.difference(now)).abs().compareTo((b.targetDate!.difference(now)).abs()));
    final plan = candidates.first;

    final prevQty = plan.purchasedQuantity;
    final prevAvg = plan.purchasedAvgPrice;
    final newQty = prevQty + qty;
    plan.purchasedQuantity = newQty;
    plan.purchasedAvgPrice = newQty > 0 ? ((prevAvg * prevQty) + (price * qty)) / newQty : price;
    if (newQty >= plan.targetQuantity) {
      plan.status = PlanStatus.done;
    }
    await StorageService.updatePlan(plan);
  }
}
