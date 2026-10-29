import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/models/purchase.dart';
import 'package:invest_tracker/services/payout_forecast_service.dart';
import 'package:invest_tracker/services/tax_service.dart';

/// Налог с продаж по типу счёта и налог с выплат. Хранилище не нужно:
/// сделки передаются напрямую, ставка без настроек — 13%.
void main() {
  Purchase trade(String id, DateTime date, double qty, double price, {bool sell = false}) => Purchase(
        id: id,
        date: date,
        ticker: 'SBER',
        name: 'Сбербанк',
        type: AssetType.stock,
        quantity: qty,
        pricePerUnit: price,
        isSell: sell,
      );

  // Куплено 10 шт по 100, через 4 года продано по 150: прибыль 500 ₽.
  final longHold = [
    trade('b1', DateTime(2020, 1, 10), 10, 100),
    trade('s1', DateTime(2024, 3, 1), 10, 150, sell: true),
  ];
  // То же, но продано через полгода.
  final shortHold = [
    trade('b2', DateTime(2025, 1, 10), 10, 100),
    trade('s2', DateTime(2025, 7, 1), 10, 150, sell: true),
  ];

  SaleTaxResult sale(List<Purchase> list, TaxRegime r, String id) =>
      TaxService.saleTaxBreakdown(purchases: list, regimeOverride: r)[id]!;

  group('налог с продаж', () {
    test('обычный счёт: больше 3 лет владения — льгота, налога нет', () {
      final r = sale(longHold, TaxRegime.regular, 's1');
      expect(r.realizedGainRub, closeTo(500, 1e-9));
      expect(r.taxableGainRub, 0);
      expect(r.taxRub, 0);
      expect(r.hasLdvPortion, isTrue);
    });

    test('обычный счёт: меньше 3 лет — 13% с прибыли, удерживается сразу', () {
      final r = sale(shortHold, TaxRegime.regular, 's2');
      expect(r.taxRub, closeTo(65, 1e-9));
      expect(r.dueRub, closeTo(65, 1e-9));
      expect(r.deferred, isFalse);
    });

    test('на ИИС льготы за 3 года нет', () {
      final r = sale(longHold, TaxRegime.iis3, 's1');
      expect(r.hasLdvPortion, isFalse);
      expect(r.taxableGainRub, closeTo(500, 1e-9));
    });

    test('ИИС-3 и тип Б: налог только при досрочном закрытии, по плану — 0', () {
      for (final regime in [TaxRegime.iis3, TaxRegime.iisB]) {
        final r = sale(shortHold, regime, 's2');
        expect(r.taxRub, closeTo(65, 1e-9), reason: '$regime');
        expect(r.dueRub, 0, reason: '$regime');
        expect(r.deferred, isTrue);
        expect(r.exemptAtTerm, isTrue);
      }
    });

    test('ИИС типа А: налог есть, но удерживается при закрытии', () {
      final r = sale(shortHold, TaxRegime.iisA, 's2');
      expect(r.dueRub, closeTo(65, 1e-9));
      expect(r.deferred, isTrue);
      expect(r.exemptAtTerm, isFalse);
    });

    test('убыток — без налога на любом счёте', () {
      final loss = [
        trade('b3', DateTime(2025, 1, 10), 10, 150),
        trade('s3', DateTime(2025, 7, 1), 10, 100, sell: true),
      ];
      for (final regime in TaxRegime.values) {
        expect(sale(loss, regime, 's3').taxRub, 0);
      }
    });
  });

  group('подпись налога у продажи', () {
    test('ИИС-3: «налог 0 ₽» и сумма при досрочном закрытии', () {
      final label = saleTaxLabel(sale(shortHold, TaxRegime.iis3, 's2'))!;
      expect(label, startsWith('налог 0 ₽'));
      expect(label, contains('досрочном'));
    });

    test('обычный счёт с льготой — «без налога (ЛДВ)»', () {
      expect(saleTaxLabel(sale(longHold, TaxRegime.regular, 's1')), 'без налога (ЛДВ)');
    });
  });

  group('налог с выплат в прогнозе', () {
    test('с дивидендов вычитается, купоны приходят целиком', () {
      expect(PayoutForecastService.netFactorFor('Дивиденд'), closeTo(0.87, 1e-9));
      expect(PayoutForecastService.netFactorFor('Купон'), 1);
    });
  });

  test('режимы: льгота — только на обычном счёте, без налога после срока — ИИС-3 и Б', () {
    expect(TaxService.ldvAppliesFor(TaxRegime.regular), isTrue);
    expect(TaxService.ldvAppliesFor(TaxRegime.iisA), isFalse);
    expect(TaxService.exemptAtTermFor(TaxRegime.iis3), isTrue);
    expect(TaxService.exemptAtTermFor(TaxRegime.iisB), isTrue);
    expect(TaxService.exemptAtTermFor(TaxRegime.iisA), isFalse);
    expect(TaxService.deferredFor(TaxRegime.regular), isFalse);
  });
}
