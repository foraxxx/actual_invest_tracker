import 'analytics_service.dart';
import 'cash_service.dart';
import 'cbr_service.dart';

/// Сколько заработал портфель по сравнению с ростом цен и с деньгами под
/// ключевую ставку за тот же период.
class RealReturn {
  final DateTime from;
  final DateTime to;

  /// Свои деньги в деле: счёт на начало периода плюс пополнения минус выводы.
  final double base;

  /// Счёт сейчас: бумаги и свободные деньги.
  final double portfolio;

  /// Сколько стоили бы те же деньги, если бы просто дорожали вместе с ценами.
  final double inflation;

  /// Сколько было бы, если держать те же деньги под ключевую ставку.
  final double keyRate;

  const RealReturn({
    required this.from,
    required this.to,
    required this.base,
    required this.portfolio,
    required this.inflation,
    required this.keyRate,
  });

  double get portfolioPct => (portfolio / base - 1) * 100;
  double get inflationPct => (inflation / base - 1) * 100;
  double get keyRatePct => (keyRate / base - 1) * 100;

  /// На сколько процентных пунктов портфель обогнал инфляцию.
  double get vsInflation => portfolioPct - inflationPct;

  /// На сколько процентных пунктов портфель обогнал ключевую ставку.
  double get vsKeyRate => portfolioPct - keyRatePct;

  /// Прибавка покупательной способности в рублях.
  double get realGainRub => portfolio - inflation;
}

class RealReturnService {
  RealReturnService._();

  /// Считает для периода главного экрана. null — если нет данных Банка России
  /// или в периоде нет своих денег.
  static RealReturn? forPeriod(PeriodFilter f, {DateTime? now}) {
    final to = now ?? DateTime.now();
    final summary = CashService.summary();
    final moves = [...summary.moves]..sort((a, b) => a.date.compareTo(b.date));
    if (moves.isEmpty) return null;

    final start = AnalyticsService.periodStart(f, now: to);
    final from = start == null || start.isBefore(moves.first.date) ? moves.first.date : start;

    double startAccount = 0;
    if (start != null && start.isAfter(moves.first.date)) {
      double cashAt = 0;
      for (final m in moves) {
        if (m.date.isAfter(start)) break;
        cashAt += m.amountRub;
      }
      final holdings = AnalyticsService.holdingsAt(date: start).values.fold(0.0, (s, h) => s + h.valueRub);
      startAccount = holdings + (cashAt < 0 ? 0.0 : cashAt);
    }

    final flows = <(DateTime, double)>[
      for (final m in moves)
        if ((start == null || m.date.isAfter(start)) &&
            (m.kind == CashMoveKind.deposit ||
                m.kind == CashMoveKind.autoDeposit ||
                m.kind == CashMoveKind.withdrawal))
          (m.date, m.amountRub),
    ];

    final end = AnalyticsService.currentPortfolioValueRub() + summary.cash;
    return compute(from: from, to: to, startAccount: startAccount, flows: flows, endAccount: end);
  }

  /// Ядро расчёта: каждый рубль, пришедший на счёт, «растёт» вместе с ценами
  /// (или под ключевую ставку) с даты поступления до сегодня. Выводы
  /// вычитаются так же, со дня вывода.
  static RealReturn? compute({
    required DateTime from,
    required DateTime to,
    required double startAccount,
    required List<(DateTime, double)> flows,
    required double endAccount,
  }) {
    final base = startAccount + flows.fold(0.0, (s, f) => s + f.$2);
    if (base <= 0) return null;

    final startInfl = CbrService.inflationFactor(from, to);
    final startKey = CbrService.keyRateFactor(from, to);
    if (startInfl == null || startKey == null) return null;

    double infl = startAccount * startInfl;
    double key = startAccount * startKey;
    for (final f in flows) {
      final fi = CbrService.inflationFactor(f.$1, to);
      final fk = CbrService.keyRateFactor(f.$1, to);
      if (fi == null || fk == null) return null;
      infl += f.$2 * fi;
      key += f.$2 * fk;
    }

    return RealReturn(
      from: from,
      to: to,
      base: base,
      portfolio: endAccount,
      inflation: infl,
      keyRate: key,
    );
  }
}
