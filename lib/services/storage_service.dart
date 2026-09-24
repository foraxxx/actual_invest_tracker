import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/deposit.dart';
import '../models/purchase.dart';
import '../models/income.dart';
import '../models/plan.dart';
import 'portfolio_service.dart';

/// Единая точка доступа к локальному хранилищу.
/// Всё хранится в файлах Hive на диске устройства — без БД-сервера,
/// без интернета, полностью офлайн.
///
/// Данные (сделки/доходы/пополнения/планы) физически разложены по разным
/// Hive-боксам в зависимости от активного портфеля (см. PortfolioService):
/// у портфеля по умолчанию (id == PortfolioService.defaultId) боксы — без
/// суффикса, это те же боксы, что были всегда, поэтому у пользователей,
/// обновившихся со старой версии (когда портфелей ещё не было), ничего не
/// теряется и не требует миграции. У остальных портфелей — суффикс "_<id>".
class StorageService {
  static late Box<Deposit> depositsBox;
  static late Box<Purchase> purchasesBox;
  static late Box<Income> incomesBox;
  static late Box<Plan> plansBox;

  /// Увеличивается при любом изменении данных (покупка, продажа, доход,
  /// план), а также при переключении портфеля.
  /// Экраны вроде дашборда слушают это значение через ValueListenableBuilder,
  /// чтобы автоматически перечитывать статистику без ручного refresh.
  static final ValueNotifier<int> dataVersion = ValueNotifier(0);

  static String _suffix(String portfolioId) =>
      portfolioId == PortfolioService.defaultId ? '' : '_$portfolioId';

  /// Регистрирует Hive-адаптеры моделей. Вызывается один раз при старте,
  /// до PortfolioService.init() и до открытия боксов.
  static void registerAdapters() {
    Hive.registerAdapter(DepositAdapter());
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(PurchaseAdapter());
    Hive.registerAdapter(IncomeTypeAdapter());
    Hive.registerAdapter(IncomeAdapter());
    Hive.registerAdapter(PlanStatusAdapter());
    Hive.registerAdapter(PlanAdapter());
  }

  static Future<void> init() async {
    await _openBoxesFor(PortfolioService.activeId);
  }

  static Future<void> _openBoxesFor(String portfolioId) async {
    final s = _suffix(portfolioId);
    depositsBox = await Hive.openBox<Deposit>('deposits$s');
    purchasesBox = await Hive.openBox<Purchase>('purchases$s');
    incomesBox = await Hive.openBox<Income>('incomes$s');
    plansBox = await Hive.openBox<Plan>('plans$s');
  }

  /// Вызывается PortfolioService при переключении активного портфеля:
  /// закрывает текущие боксы и открывает боксы нужного портфеля (создаются
  /// пустыми, если для этого портфеля их ещё не было).
  static Future<void> reopenBoxesFor(String portfolioId) async {
    await depositsBox.close();
    await purchasesBox.close();
    await incomesBox.close();
    await plansBox.close();
    await _openBoxesFor(portfolioId);
    _bump();
  }

  /// Удаляет с диска боксы указанного портфеля — используется при удалении
  /// портфеля целиком. Вызывается ПОСЛЕ того, как активный портфель уже
  /// переключён на другой (иначе удалили бы то, что сейчас открыто).
  static Future<void> deleteBoxesFor(String portfolioId) async {
    final s = _suffix(portfolioId);
    await Hive.deleteBoxFromDisk('deposits$s');
    await Hive.deleteBoxFromDisk('purchases$s');
    await Hive.deleteBoxFromDisk('incomes$s');
    await Hive.deleteBoxFromDisk('plans$s');
  }

  /// Читает сделки и доходы указанного портфеля, НЕ трогая текущие активные
  /// боксы (depositsBox/purchasesBox/...) и не переключая активный портфель.
  /// Для активного портфеля просто возвращает уже загруженные данные. Для
  /// остальных — открывает их боксы отдельно и сразу закрывает после чтения
  /// (иначе они оставались бы висеть открытыми до конца жизни приложения).
  /// Используется страницей со списком портфелей, чтобы посчитать
  /// стоимость/прибыль КАЖДОГО портфеля, включая неактивные сейчас.
  ///
  /// Чтения выстроены в очередь. Причина: бокс здесь открывается и тут же
  /// закрывается, а Hive на повторный openBox отдаёт ТОТ ЖЕ экземпляр. Если
  /// два чтения одного портфеля идут одновременно, первое закрывает бокс,
  /// пока второе ещё читает, и всё падает на «Box has already been closed».
  /// Список портфелей и обновление котировок читают данные независимо друг от
  /// друга, так что пересечение здесь — обычное дело, а не редкий случай.
  static Future<({List<Purchase> purchases, List<Income> incomes})> readDataFor(
    String portfolioId,
  ) {
    final next = _readQueue.then((_) => _readDataForNow(portfolioId));
    // В очереди держим только факт завершения, без результата и без ошибки:
    // иначе одно неудачное чтение обрушило бы все последующие.
    _readQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<void> _readQueue = Future.value();

  static Future<({List<Purchase> purchases, List<Income> incomes})> _readDataForNow(
    String portfolioId,
  ) async {
    if (portfolioId == PortfolioService.activeId) {
      return (purchases: purchases, incomes: incomes);
    }
    final s = _suffix(portfolioId);
    final pBox = await Hive.openBox<Purchase>('purchases$s');
    final iBox = await Hive.openBox<Income>('incomes$s');
    final result = (purchases: pBox.values.toList(), incomes: iBox.values.toList());
    await pBox.close();
    await iBox.close();
    return result;
  }

  /// Тикеры из ВСЕХ портфелей сразу, а не только из активного.
  ///
  /// Нужно для обновления котировок: стоимость неактивного портфеля на
  /// стартовом экране считается по кэшу цен, и если бумаги этого портфеля
  /// никогда не запрашивались у биржи, там навсегда останется цена с того
  /// момента, когда портфель последний раз был активным.
  static Future<Set<String>> allPortfolioTickers() async {
    final result = <String>{};
    for (final meta in PortfolioService.list) {
      final data = await readDataFor(meta.id);
      for (final purchase in data.purchases) {
        final ticker = purchase.ticker.trim().toUpperCase();
        if (ticker.isNotEmpty) result.add(ticker);
      }
    }
    return result;
  }

  static void _bump() => dataVersion.value++;

  // --- Deposits ---
  static List<Deposit> get deposits => depositsBox.values.toList();
  static Future<void> addDeposit(Deposit d) async {
    await depositsBox.put(d.id, d);
    _bump();
  }

  static Future<void> deleteDeposit(String id) async {
    await depositsBox.delete(id);
    _bump();
  }

  // --- Purchases ---
  static List<Purchase> get purchases => purchasesBox.values.toList();
  static Future<void> addPurchase(Purchase p) async {
    await purchasesBox.put(p.id, p);
    _bump();
  }

  static Future<void> deletePurchase(String id) async {
    // Если удаляемая сделка была засчитана в план — пересчитываем прогресс
    // плана ПОСЛЕ удаления, иначе он останется завышенным навсегда (старая
    // версия просто копила счётчик и никогда не откатывала его).
    final purchase = purchasesBox.get(id);
    await purchasesBox.delete(id);
    if (purchase?.planId != null) {
      await _recomputePlanProgress(purchase!.planId!);
    }
    _bump();
  }

  /// Привязывает уже сохранённую сделку к плану (см. Purchase.planId) и
  /// пересчитывает прогресс плана из фактических сделок. Используется вместо
  /// прежнего ручного накопления счётчика — так удаление/правка сделки не
  /// расходится с тем, что показывает план.
  ///
  /// [quantity] — сколько бумаг засчитать. Не задано — вся сделка. Лишнее
  /// сверх нужного плану остаётся обычной покупкой без плана.
  static Future<void> applyPurchaseToPlan(String purchaseId, String planId, {double? quantity}) async {
    final purchase = purchasesBox.get(purchaseId);
    if (purchase == null) return;
    purchase.planId = planId;
    // Пустое значение хранится, когда в план идёт вся сделка: тогда запись
    // ничем не отличается от сделок, созданных до появления этого поля.
    purchase.planQuantity =
        quantity == null || quantity >= purchase.quantity ? null : quantity;
    await purchase.save();
    await _recomputePlanProgress(planId);
    _bump();
  }

  /// Пересчитывает purchasedQuantity/purchasedAvgPrice плана заново из всех
  /// сделок с этим planId — а не прибавляет к текущему значению. Так прогресс
  /// плана всегда соответствует реально существующим сделкам, даже если
  /// какая-то из них была изменена или удалена позже.
  static Future<void> _recomputePlanProgress(String planId) async {
    final plan = plansBox.get(planId);
    if (plan == null) return;
    final linked = purchases.where((p) => p.planId == planId && !p.isSell).toList();
    // Считается засчитанная часть сделки, а не вся: иначе покупка на 10 штук
    // в план, которому не хватало пяти, опять перевыполнила бы его.
    final qty = linked.fold(0.0, (s, p) => s + p.quantityInPlan);
    final avg = qty > 0 ? linked.fold(0.0, (s, p) => s + p.quantityInPlan * p.pricePerUnit) / qty : 0.0;
    plan.purchasedQuantity = qty;
    plan.purchasedAvgPrice = avg;
    if (plan.status == PlanStatus.active && plan.targetQuantity > 0 && qty >= plan.targetQuantity) {
      plan.status = PlanStatus.done;
    } else if (plan.status == PlanStatus.done && qty < plan.targetQuantity) {
      // План был завершён автоматически по количеству — раз одна из сделок
      // пропала, количество больше не достигнуто. Ручную отметку "Выполнен"
      // (например, из-за исчерпанного бюджета при выросшей цене) это не
      // трогает, если только сама отмеченная сделка не была удалена.
      plan.status = PlanStatus.active;
    }
    await plan.save();
  }

  // --- Incomes ---
  static List<Income> get incomes => incomesBox.values.toList();
  static Future<void> addIncome(Income i) async {
    await incomesBox.put(i.id, i);
    _bump();
  }

  static Future<void> deleteIncome(String id) async {
    await incomesBox.delete(id);
    _bump();
  }

  // --- Plans ---
  static List<Plan> get plans => plansBox.values.toList();
  static Future<void> addPlan(Plan p) async {
    await plansBox.put(p.id, p);
    _bump();
  }

  static Future<void> deletePlan(String id) async {
    await plansBox.delete(id);
    _bump();
  }

  static Future<void> updatePlan(Plan p) async {
    await p.save();
    _bump();
  }

  /// Атомарно, с точки зрения приложения, заменяет основные финансовые
  /// коллекции. Hive не поддерживает транзакцию между несколькими box, поэтому
  /// при любой ошибке восстанавливаем снимок всех четырёх коллекций.
  static Future<void> replaceFinancialData({
    required Iterable<Deposit> deposits,
    required Iterable<Purchase> purchases,
    required Iterable<Income> incomes,
    required Iterable<Plan> plans,
  }) async {
    final oldDeposits = Map<dynamic, Deposit>.from(depositsBox.toMap());
    final oldPurchases = Map<dynamic, Purchase>.from(purchasesBox.toMap());
    final oldIncomes = Map<dynamic, Income>.from(incomesBox.toMap());
    final oldPlans = Map<dynamic, Plan>.from(plansBox.toMap());

    Future<void> writeAll() async {
      await depositsBox.clear();
      await purchasesBox.clear();
      await incomesBox.clear();
      await plansBox.clear();
      await depositsBox.putAll({for (final value in deposits) value.id: value});
      await purchasesBox.putAll({for (final value in purchases) value.id: value});
      await incomesBox.putAll({for (final value in incomes) value.id: value});
      await plansBox.putAll({for (final value in plans) value.id: value});
    }

    try {
      await writeAll();
    } catch (_) {
      await depositsBox.clear();
      await purchasesBox.clear();
      await incomesBox.clear();
      await plansBox.clear();
      await depositsBox.putAll(oldDeposits);
      await purchasesBox.putAll(oldPurchases);
      await incomesBox.putAll(oldIncomes);
      await plansBox.putAll(oldPlans);
      rethrow;
    }
    _bump();
  }
}
