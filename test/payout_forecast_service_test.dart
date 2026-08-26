import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/moex_service.dart';
import 'package:invest_tracker/services/payout_forecast_service.dart';

/// Прогноз дивидендов. Проверяется главное свойство расчёта: незаконченный
/// текущий год не должен занижать ожидание.
///
/// Причина, по которой эти тесты существуют: биржа вносит свежие выплаты в
/// свой справочник с задержкой, поэтому по текущему году данные почти всегда
/// неполные. Если считать такой год наравне с завершёнными, он занижает и
/// базу прогноза, и темп роста — ошибка складывается дважды.
void main() {
  MoexPayout dividend(DateTime date, double amount) => MoexPayout(
        date: date,
        amount: amount,
        currency: 'SUR',
        kind: 'Дивиденд',
      );

  final year = DateTime.now().year;

  group('прогноз дивидендов', () {
    test('пустая история не даёт прогноза', () {
      expect(PayoutForecastService.dividendPerUnit(const []).value, 0);
    });

    test('растущие выплаты переносятся вперёд с темпом роста', () {
      final result = PayoutForecastService.dividendPerUnit([
        dividend(DateTime(year - 3, 7, 10), 20),
        dividend(DateTime(year - 2, 7, 10), 24),
        dividend(DateTime(year - 1, 7, 10), 28.8),
      ]);
      // Темп +20% в год, последняя полная выплата 28.8 → ожидаем около 34.6.
      expect(result.value, closeTo(34.56, 0.2));
    });

    test('неполный текущий год не занижает базу прогноза', () {
      final full = [
        dividend(DateTime(year - 2, 7, 10), 20),
        dividend(DateTime(year - 1, 7, 10), 22),
      ];
      final withPartial = [
        ...full,
        // Биржа успела внести только первую из двух выплат текущего года.
        dividend(DateTime(year, 3, 10), 6),
      ];
      expect(
        PayoutForecastService.dividendPerUnit(withPartial).value,
        closeTo(PayoutForecastService.dividendPerUnit(full).value, 0.001),
        reason: 'частично внесённый текущий год не должен менять прогноз',
      );
    });

    test('выплата без даты отсечки не попадает в годовую статистику', () {
      final base = [
        dividend(DateTime(year - 2, 7, 10), 20),
        dividend(DateTime(year - 1, 7, 10), 22),
      ];
      final withAnnounced = [
        ...base,
        // Совет директоров рекомендовал сумму, дату биржа ещё не проставила.
        // Внутри такой выплате подставляется служебная дата далеко впереди —
        // важно, что в расчёт по годам она не идёт.
        MoexPayout(
          date: DateTime.now().add(const Duration(days: 365 * 5)),
          amount: 25,
          currency: 'SUR',
          kind: 'Дивиденд',
          dateKnown: false,
        ),
      ];
      expect(
        PayoutForecastService.dividendPerUnit(withAnnounced).value,
        closeTo(PayoutForecastService.dividendPerUnit(base).value, 0.001),
      );
    });

    test('единственная выплата в текущем году всё же даёт прогноз', () {
      final result = PayoutForecastService.dividendPerUnit([
        dividend(DateTime(year, 5, 20), 15),
      ]);
      expect(result.value, closeTo(15, 0.001));
    });
  });
}
