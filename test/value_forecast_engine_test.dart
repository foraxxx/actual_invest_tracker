import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/value_forecast_engine.dart';
import 'package:invest_tracker/services/value_forecast_service.dart';

/// Прогноз стоимости портфеля.
///
/// Главное, что здесь проверяется, — что разбивка честная: статьи всегда
/// складываются в итог, а «эффект реинвестирования» — это действительно
/// эффект реинвестирования, а не мусорная корзина для ошибок расчёта.
void main() {
  final start = DateTime(2026, 9, 21);

  final market = MarketAssumptions(
    stockDrift: math.log(1.06),
    stockVolatility: 0.25,
    reinvestYield: const {
      ForecastScenario.pessimistic: 0.08,
      ForecastScenario.realistic: 0.12,
      ForecastScenario.optimistic: 0.16,
    },
    source: 'тест',
  );

  // Облигация с дисконтом, частичным погашением и погашением внутри горизонта.
  final bond = ForecastAsset(
    ticker: 'BOND',
    kind: ForecastAssetKind.bond,
    qty: 100,
    price: 950,
    face: 1000,
    maturity: DateTime(2028, 3, 15),
    coupons: [
      CashEvent(DateTime(2026, 12, 15), 40),
      CashEvent(DateTime(2027, 6, 15), 40),
      CashEvent(DateTime(2027, 12, 15), 30),
      CashEvent(DateTime(2028, 3, 15), 30),
    ],
    amortizations: [
      CashEvent(DateTime(2027, 6, 15), 250),
      CashEvent(DateTime(2028, 3, 15), 750),
    ],
  );

  // Флоатер: будущие купоны биржа отдаёт нулями, известен только прошлый.
  final floater = ForecastAsset(
    ticker: 'FLOAT',
    kind: ForecastAssetKind.bond,
    qty: 10,
    price: 1000,
    face: 1000,
    maturity: DateTime(2030, 1, 1),
    coupons: [
      CashEvent(DateTime(2026, 8, 1), 45),
      CashEvent(DateTime(2026, 11, 1), 0),
      CashEvent(DateTime(2027, 2, 1), 0),
    ],
  );

  final stock = ForecastAsset(
    ticker: 'STOCK',
    kind: ForecastAssetKind.equity,
    qty: 200,
    price: 300,
    dividendsLastYear: [CashEvent(DateTime(2026, 7, 10), 33)],
  );

  const flat = ForecastAsset(ticker: 'USD', kind: ForecastAssetKind.flat, qty: 1, price: 5000);

  final portfolio = [bond, floater, stock, flat];

  ForecastResult run(
    List<ForecastAsset> assets,
    ForecastScenario s,
    int months, {
    bool reinvest = true,
    double freeCash = 0,
    MarketAssumptions? m,
  }) =>
      ValueForecastEngine.simulate(
        assets: assets,
        market: m ?? market,
        scenario: s,
        start: start,
        months: months,
        freeCash: freeCash,
        reinvest: reinvest,
      );

  group('разбивка', () {
    test('без реинвестирования его эффект ровно ноль', () {
      // Главный инвариант: если выплаты просто копятся деньгами, любое
      // ненулевое значение здесь — ошибка в учёте, а не «эффект».
      for (final s in ForecastScenario.values) {
        final b = run(portfolio, s, 60, reinvest: false, freeCash: 1234).breakdown;
        expect(b.reinvestment, closeTo(0, 1e-6), reason: s.name);
      }
    });

    test('статьи всегда складываются в итог', () {
      for (final s in ForecastScenario.values) {
        final b = run(portfolio, s, 60, freeCash: 1234).breakdown;
        final sum = b.start +
            b.coupons +
            b.dividends +
            b.bondsToPar +
            b.stockGrowth +
            b.reinvestment +
            b.plannedInvested +
            b.plannedIncome;
        expect(sum, closeTo(b.end, 1e-6), reason: s.name);
      }
    });

    test('при росте рынка реинвестирование даёт неотрицательный эффект', () {
      expect(run(portfolio, ForecastScenario.realistic, 60).breakdown.reinvestment, greaterThanOrEqualTo(0));
    });
  });

  group('облигации', () {
    test('до погашения: итог — номинал плюс купоны', () {
      final b = run([bond], ForecastScenario.realistic, 24, reinvest: false).breakdown;
      expect(b.end, closeTo(100 * (1000 + 40 + 40 + 30 + 30), 1e-6));
      expect(b.bondsToPar, closeTo(100 * (1000 - 950), 1e-6));
      expect(b.coupons, closeTo(100 * 140, 1e-6));
    });

    test('не объявленный купон флоатера берётся по последнему известному', () {
      // Без этого будущие купоны флоатера молча считались бы нулём.
      final b = run([floater], ForecastScenario.realistic, 6, reinvest: false).breakdown;
      expect(b.coupons, closeTo(10 * 45 * 2, 1e-6));
    });

    test('до погашения одинаковы во всех сценариях', () {
      // Сценарии различаются для облигаций только доходностью денег ПОСЛЕ
      // погашения — до него расчёт идёт по графику биржи.
      final p = run([bond], ForecastScenario.pessimistic, 17).breakdown.end;
      final o = run([bond], ForecastScenario.optimistic, 17).breakdown.end;
      expect(p, closeTo(o, 1e-6));
    });

    test('погашение в пределах срока попадает в пометки графика', () {
      final m = ValueForecastEngine.maturitiesWithin(portfolio, start, 24);
      expect(m, [DateTime(2028, 3, 15)]);
    });
  });

  group('акции', () {
    test('сценарии упорядочены', () {
      final p = run(portfolio, ForecastScenario.pessimistic, 60).breakdown.end;
      final r = run(portfolio, ForecastScenario.realistic, 60).breakdown.end;
      final o = run(portfolio, ForecastScenario.optimistic, 60).breakdown.end;
      expect(p < r && r < o, isTrue);
    });

    test('веер расширяется со временем', () {
      // Неопределённость через год и через пять лет — разная. Постоянные
      // ставки дали бы расхождение с первого месяца, что неверно.
      double width(int months) =>
          run([stock], ForecastScenario.optimistic, months).breakdown.end -
          run([stock], ForecastScenario.pessimistic, months).breakdown.end;
      expect(width(12), lessThan(width(60)));
    });

    test('дивиденды прошлого года повторяются через год', () {
      final still = MarketAssumptions(
        stockDrift: 0,
        stockVolatility: 0,
        reinvestYield: market.reinvestYield,
        source: 'тест',
      );
      final b = run([stock], ForecastScenario.realistic, 12, reinvest: false, m: still).breakdown;
      expect(b.dividends, closeTo(200 * 33, 1e-6));
    });
  });

  group('история индекса', () {
    test('меньше трёх лет истории не используется', () {
      final closes = [for (int i = 0; i < 30; i++) 3000.0];
      expect(ValueForecastService.monthlyStats(closes), isNull);
    });

    test('ровный индекс даёт нулевой рост', () {
      final closes = [for (int i = 0; i < 61; i++) 3000.0 * (i.isEven ? 1.0 : 1.0001)];
      final stats = ValueForecastService.monthlyStats(closes)!;
      expect(stats.drift, closeTo(0, 1e-3));
      expect(stats.years, 5);
    });

    test('устойчивый рост восстанавливается из истории', () {
      // 1% в месяц — это ln(1.01)·12 ≈ 0.119 годового дрейфа.
      final closes = [for (int i = 0; i < 121; i++) (1000.0 * math.pow(1.01, i)).toDouble()];
      final stats = ValueForecastService.monthlyStats(closes)!;
      expect(stats.drift, closeTo(math.log(1.01) * 12, 1e-9));
    });
  });

  group('плановые покупки', () {
    // Рынок без роста и разброса: единственное, что может изменить стоимость,
    // — сама плановая покупка. Так проверяется, что она не создаёт прибыли из
    // воздуха.
    final flatMarket = MarketAssumptions(
      stockDrift: 0,
      stockVolatility: 0,
      reinvestYield: const {
        ForecastScenario.pessimistic: 0,
        ForecastScenario.realistic: 0,
        ForecastScenario.optimistic: 0,
      },
      source: 'тест',
    );

    // Акция 300 ₽ без дивидендов — итоги сходятся до копейки.
    ForecastAsset equity({
      double qty = 200,
      List<PlannedBuy> planned = const [],
      List<CashEvent> dividends = const [],
    }) =>
        ForecastAsset(
          ticker: 'EQ',
          kind: ForecastAssetKind.equity,
          qty: qty,
          price: 300,
          dividendsLastYear: dividends,
          plannedBuys: planned,
        );

    PlannedBuy buy(DateTime date, double qty) => PlannedBuy(date, qty);

    ForecastResult flatRun(
      List<ForecastAsset> assets,
      int months, {
      double freeCash = 0,
      bool reinvest = false,
      DateTime? from,
    }) =>
        ValueForecastEngine.simulate(
          assets: assets,
          market: flatMarket,
          scenario: ForecastScenario.realistic,
          start: from ?? start,
          months: months,
          freeCash: freeCash,
          reinvest: reinvest,
        );

    test('без планов новые статьи разбивки равны нулю', () {
      final r = run(portfolio, ForecastScenario.realistic, 36);
      expect(r.breakdown.plannedInvested, 0);
      expect(r.breakdown.plannedIncome, 0);
      expect(r.plannedSpent, 0);
    });

    test('статьи разбивки складываются в итог при любых настройках', () {
      final freshBond = ForecastAsset(
        ticker: 'NEW',
        kind: ForecastAssetKind.bond,
        qty: 0,
        price: 980,
        face: 1000,
        maturity: DateTime(2029, 6, 1),
        coupons: [
          CashEvent(DateTime(2026, 12, 1), 35),
          CashEvent(DateTime(2027, 6, 1), 35),
          CashEvent(DateTime(2027, 12, 1), 35),
        ],
        plannedBuys: [buy(DateTime(2026, 12, 20), 50), buy(DateTime(2027, 3, 10), 20)],
      );
      final assets = [
        bond,
        stock.withPlannedBuys([buy(DateTime(2027, 1, 15), 100), buy(DateTime(2026, 6, 1), 30)]),
        freshBond,
      ];
      for (final s in ForecastScenario.values) {
        for (final cash in [0.0, 15000.0]) {
          for (final reinvest in [true, false]) {
            final b = run(assets, s, 60, freeCash: cash, reinvest: reinvest).breakdown;
            final sum = b.start +
                b.coupons +
                b.dividends +
                b.bondsToPar +
                b.stockGrowth +
                b.reinvestment +
                b.plannedInvested +
                b.plannedIncome;
            expect(sum, closeTo(b.end, 1e-6), reason: '${s.name} cash=$cash reinvest=$reinvest');
          }
        }
      }
    });

    test('строки по текущему портфелю не зависят от галки', () {
      // Включение планов не должно менять ни одну строку по тому, что уже
      // лежит в портфеле, — вся разница уходит в две новые статьи.
      final planned = [
        bond,
        stock.withPlannedBuys([buy(DateTime(2027, 1, 15), 100)]),
      ];
      final plain = [bond, stock];
      for (final s in ForecastScenario.values) {
        final a = run(plain, s, 60).breakdown;
        final b = run(planned, s, 60).breakdown;
        expect(b.start, closeTo(a.start, 1e-9), reason: s.name);
        expect(b.coupons, closeTo(a.coupons, 1e-9), reason: s.name);
        expect(b.dividends, closeTo(a.dividends, 1e-9), reason: s.name);
        expect(b.bondsToPar, closeTo(a.bondsToPar, 1e-9), reason: s.name);
        expect(b.stockGrowth, closeTo(a.stockGrowth, 1e-9), reason: s.name);
        expect(b.reinvestment, closeTo(a.reinvestment, 1e-9), reason: s.name);
      }
    });

    test('покупка не создаёт мгновенной прибыли', () {
      final r = flatRun([equity(planned: [buy(DateTime(2026, 12, 20), 100)])], 12);
      expect(r.plannedSpent, closeTo(30000, 1e-6));
      expect(r.breakdown.plannedInvested, closeTo(30000, 1e-6));
      expect(r.breakdown.plannedIncome, closeTo(0, 1e-9));
    });

    test('сначала тратятся свободные деньги, потом новые', () {
      final assets = [equity(planned: [buy(DateTime(2026, 12, 20), 100)])];
      expect(flatRun(assets, 6, freeCash: 10000).breakdown.plannedInvested, closeTo(20000, 1e-6));
      expect(flatRun(assets, 6, freeCash: 50000).breakdown.plannedInvested, closeTo(0, 1e-9));
    });

    test('деньги от погашённой облигации тратятся раньше новых', () {
      final matured = ForecastAsset(
        ticker: 'B',
        kind: ForecastAssetKind.bond,
        qty: 100,
        price: 1000,
        face: 1000,
        maturity: DateTime(2027, 1, 20),
      );
      final r = flatRun(
        [matured, equity(planned: [buy(DateTime(2027, 5, 10), 100)])],
        12,
        reinvest: true,
      );
      expect(r.plannedSpent, closeTo(30000, 1e-6));
      expect(r.breakdown.plannedInvested, closeTo(0, 1e-9));
      // Плоский рынок и ни рубля извне: стоимость не могла измениться.
      expect(r.breakdown.end, closeTo(r.breakdown.start, 1e-6));
    });

    test('просроченный план выполняется в первый месяц', () {
      final r = flatRun([equity(planned: [buy(DateTime(2026, 1, 10), 100)])], 6);
      expect(r.points[1].value - r.points[0].value, closeTo(30000, 1e-6));
    });

    test('план за пределами срока не учитывается', () {
      final r = flatRun([equity(planned: [buy(DateTime(2029, 6, 10), 100)])], 12);
      expect(r.plannedSpent, 0);
      expect(r.breakdown.plannedInvested, 0);
    });

    test('покупка на последний день месяца не теряется', () {
      // В последний день месяца первый шаг прогноза пуст, и покупка,
      // назначенная «на сегодня», не выполнилась бы при сравнении дат.
      final last = DateTime(2026, 9, 30);
      final r = flatRun([equity(planned: [buy(last, 100)])], 6, from: last);
      expect(r.plannedSpent, closeTo(30000, 1e-6));
    });

    test('бумага, которой нет в портфеле, покупается и платит купоны', () {
      final fresh = ForecastAsset(
        ticker: 'NEW',
        kind: ForecastAssetKind.bond,
        qty: 0,
        price: 1000,
        face: 1000,
        maturity: DateTime(2030, 1, 1),
        coupons: [CashEvent(DateTime(2027, 6, 1), 50), CashEvent(DateTime(2027, 12, 1), 50)],
        plannedBuys: [buy(DateTime(2027, 1, 10), 10)],
      );
      final r = flatRun([fresh], 24);
      expect(r.breakdown.plannedInvested, closeTo(10000, 1e-6));
      // Два купона по 50 ₽ на 10 бумаг.
      expect(r.breakdown.plannedIncome, closeTo(1000, 1e-6));
    });

    test('погашённую облигацию не докупают', () {
      final matured = ForecastAsset(
        ticker: 'B',
        kind: ForecastAssetKind.bond,
        qty: 10,
        price: 1000,
        face: 1000,
        maturity: DateTime(2026, 12, 10),
        plannedBuys: [buy(DateTime(2027, 3, 1), 5)],
      );
      expect(flatRun([matured], 12).plannedSpent, 0);
    });

    test('несколько планов на один месяц складываются', () {
      final r = flatRun(
        [equity(planned: [buy(DateTime(2026, 12, 3), 40), buy(DateTime(2026, 12, 25), 60)])],
        6,
      );
      expect(r.plannedSpent, closeTo(30000, 1e-6));
    });

    test('дивиденды по прежним и по купленным бумагам не смешиваются', () {
      final r = flatRun(
        [
          equity(
            dividends: [CashEvent(DateTime(2026, 7, 10), 33)],
            planned: [buy(DateTime(2026, 12, 20), 100)],
          ),
        ],
        12,
      );
      expect(r.breakdown.dividends, closeTo(200 * 33, 1e-6));
      expect(r.breakdown.plannedIncome, closeTo(100 * 33, 1e-6));
    });

    test('сценарии остаются упорядоченными с плановыми покупками', () {
      final assets = [bond, stock.withPlannedBuys([buy(DateTime(2027, 1, 15), 100)])];
      final p = run(assets, ForecastScenario.pessimistic, 60).breakdown.end;
      final r = run(assets, ForecastScenario.realistic, 60).breakdown.end;
      final o = run(assets, ForecastScenario.optimistic, 60).breakdown.end;
      expect(p < r && r < o, isTrue);
    });

    test('при росте рынка купленные акции приносят положительный доход', () {
      final growing = MarketAssumptions(
        stockDrift: math.log(1.2),
        stockVolatility: 0,
        reinvestYield: flatMarket.reinvestYield,
        source: 'тест',
      );
      final r = ValueForecastEngine.simulate(
        assets: [equity(planned: [buy(DateTime(2026, 12, 20), 100)])],
        market: growing,
        scenario: ForecastScenario.realistic,
        start: start,
        months: 36,
        reinvest: false,
      );
      expect(r.breakdown.plannedIncome, greaterThan(0));
    });
  });

  group('месяц плановой покупки', () {
    final today = DateTime(2026, 9, 21);

    test('в этом же месяце — нулевой', () {
      expect(ValueForecastEngine.stepOf(DateTime(2026, 9, 30), today), 0);
    });

    test('просроченная покупка — нулевой', () {
      expect(ValueForecastEngine.stepOf(DateTime(2025, 1, 5), today), 0);
    });

    test('считается по номеру месяца, через границу года тоже', () {
      expect(ValueForecastEngine.stepOf(DateTime(2027, 1, 15), today), 4);
      expect(ValueForecastEngine.stepOf(DateTime(2028, 9, 1), today), 24);
    });
  });
}
