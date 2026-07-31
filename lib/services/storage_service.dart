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
  static Future<({List<Purchase> purchases, List<Income> incomes})> readDataFor(
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
    await purchasesBox.delete(id);
    _bump();
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
