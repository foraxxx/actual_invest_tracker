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

  /// Планы-кандидаты для покупки этой бумаги сегодня: активные, и при этом
  /// либо без срока, либо с сроком в этом месяце или раньше (включая уже
  /// просроченные — план не перестаёт быть актуальным только из-за того, что
  /// дедлайн прошёл). Планы с датой в будущих месяцах не предлагаем — покупка
  /// сегодня не должна тихо закрывать план на следующий месяц.
  ///
  /// Отсортированы по дате: сначала те, чей срок ближе всего к сегодня,
  /// затем просроченные, план без даты — в конце. Так "ближайший" кандидат
  /// (первый в списке) можно использовать как значение по умолчанию.
  static List<Plan> candidatesFor(String ticker) {
    final now = DateTime.now();
    final endOfThisMonth = DateTime(now.year, now.month + 1, 0);
    final list = StorageService.plans
        .where((p) =>
            p.ticker.toUpperCase() == ticker.toUpperCase() &&
            p.status == PlanStatus.active &&
            (p.targetDate == null || !p.targetDate!.isAfter(endOfThisMonth)))
        .toList();
    list.sort((a, b) {
      if (a.targetDate == null && b.targetDate == null) return 0;
      if (a.targetDate == null) return 1; // без даты — в конец
      if (b.targetDate == null) return -1;
      return (a.targetDate!.difference(now)).abs().compareTo((b.targetDate!.difference(now)).abs());
    });
    return list;
  }

  /// Есть ли хоть один план-кандидат — от этого зависит, показывать ли
  /// галку «учитывать в плане» на форме покупки.
  static bool hasEligiblePlan(String ticker) => candidatesFor(ticker).isNotEmpty;

  /// Засчитывает уже сохранённую сделку в конкретный план.
  static Future<void> applyToPlan(String purchaseId, String planId) =>
      StorageService.applyPurchaseToPlan(purchaseId, planId);
}
