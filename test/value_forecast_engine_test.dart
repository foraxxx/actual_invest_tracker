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
        final sum = b.start + b.coupons + b.dividends + b.bondsToPar + b.stockGrowth + b.reinvestment;
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
}
