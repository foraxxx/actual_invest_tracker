import '../models/plan.dart';
import 'storage_service.dart';

/// Подбор планов, в которые можно засчитать покупку, и сама привязка сделки
/// к плану.
///
/// Логика одна для формы сделки и для быстрой покупки из карточки бумаги,
/// поэтому живёт отдельно, а не внутри экрана. Сама привязка "сделка -> план"
/// и пересчёт прогресса — в StorageService.applyPurchaseToPlan, здесь только
/// подбор кандидатов.
class PlanApplyService {
  PlanApplyService._();

  /// Все активные планы по бумаге, от раннего срока к позднему; планы без
  /// срока — в конце.
  ///
  /// Раньше сюда попадали только планы не дальше текущего месяца: покупка не
  /// должна была тихо закрывать план на будущее. Но планы пишутся и на год
  /// вперёд, и засчитать сделку в такой план должно быть можно. Защиту от
  /// тихого закрытия теперь даёт [defaultFor]: будущий план никогда не
  /// выбирается сам, только касанием.
  ///
  /// Завершённые и отменённые планы не предлагаются: засчитать покупку в уже
  /// выполненный план почти всегда ошибка.
  static List<Plan> candidatesFor(String ticker) {
    final list = StorageService.plans
        .where((p) => p.ticker.toUpperCase() == ticker.toUpperCase() && p.status == PlanStatus.active)
        .toList();
    list.sort((a, b) {
      if (a.targetDate == null && b.targetDate == null) return 0;
      if (a.targetDate == null) return 1;
      if (b.targetDate == null) return -1;
      return a.targetDate!.compareTo(b.targetDate!);
    });
    return list;
  }

  /// План, выбранный по умолчанию: ближайший к сегодня среди планов этого
  /// месяца, просроченных и планов без срока. Если есть только будущие —
  /// null, то есть «не учитывать»: засчитать покупку в план на март человек
  /// должен решить сам.
  static Plan? defaultFor(String ticker) {
    final now = DateTime.now();
    final endOfThisMonth = DateTime(now.year, now.month + 1, 0);
    final eligible = candidatesFor(ticker)
        .where((p) => p.targetDate == null || !p.targetDate!.isAfter(endOfThisMonth))
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) {
      if (a.targetDate == null && b.targetDate == null) return 0;
      if (a.targetDate == null) return 1;
      if (b.targetDate == null) return -1;
      return a.targetDate!.difference(now).abs().compareTo(b.targetDate!.difference(now).abs());
    });
    return eligible.first;
  }

  /// Есть ли хоть один активный план по бумаге — от этого зависит, показывать
  /// ли на форме покупки блок выбора плана.
  static bool hasEligiblePlan(String ticker) => candidatesFor(ticker).isNotEmpty;

  /// Сколько плану ещё осталось добрать.
  static double remaining(Plan plan) => (plan.targetQuantity - plan.purchasedQuantity).clamp(0, double.infinity).toDouble();

  /// Сколько бумаг из покупки на [quantity] штук пойдёт в план: не больше,
  /// чем ему осталось. Остальное — обычная покупка без плана.
  static double allocation(Plan plan, double quantity) => quantity <= 0 ? 0 : quantity.clamp(0, remaining(plan)).toDouble();

  /// Засчитывает уже сохранённую сделку в конкретный план.
  ///
  /// [quantity] — сколько бумаг засчитать, см. [allocation].
  static Future<void> applyToPlan(String purchaseId, String planId, {double? quantity}) =>
      StorageService.applyPurchaseToPlan(purchaseId, planId, quantity: quantity);
}
