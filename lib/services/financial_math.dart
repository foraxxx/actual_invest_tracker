import 'dart:math' as math;

class DatedCashFlow {
  final DateTime date;
  final double amount;
  const DatedCashFlow(this.date, this.amount);
}

class TwrPeriod {
  final double startValue;
  final double endValue;
  final double externalFlow;
  const TwrPeriod({
    required this.startValue,
    required this.endValue,
    this.externalFlow = 0,
  });
}

class FinancialMath {
  FinancialMath._();

  static double? xirrPercent(Iterable<DatedCashFlow> input) {
    final flows = input.toList()..sort((a, b) => a.date.compareTo(b.date));
    if (flows.length < 2 ||
        !flows.any((f) => f.amount < 0) ||
        !flows.any((f) => f.amount > 0)) {
      return null;
    }
    final firstDate = flows.first.date;
    double npv(double rate) {
      final base = 1 + rate;
      if (base <= 0) return double.nan;
      return flows.fold(0.0, (sum, flow) {
        final years = flow.date.difference(firstDate).inDays / 365.0;
        return sum + flow.amount / math.pow(base, years);
      });
    }

    var low = -0.9999;
    var high = 1.0;
    var lowNpv = npv(low);
    var highNpv = npv(high);
    while (lowNpv * highNpv > 0 && high < 1000000) {
      high *= 2;
      highNpv = npv(high);
    }
    if (!lowNpv.isFinite || !highNpv.isFinite || lowNpv * highNpv > 0) {
      return null;
    }
    for (var i = 0; i < 160; i++) {
      final middle = (low + high) / 2;
      final middleNpv = npv(middle);
      if (!middleNpv.isFinite) return null;
      if (middleNpv.abs() < 1e-10) return middle * 100;
      if (lowNpv * middleNpv <= 0) {
        high = middle;
      } else {
        low = middle;
        lowNpv = middleNpv;
      }
    }
    return ((low + high) / 2) * 100;
  }

  static double? twrPercent(Iterable<TwrPeriod> periods) {
    var factor = 1.0;
    var used = false;
    for (final period in periods) {
      if (period.startValue <= 0) continue;
      final periodFactor =
          (period.endValue - period.externalFlow) / period.startValue;
      if (!periodFactor.isFinite || periodFactor < 0) return null;
      factor *= periodFactor;
      used = true;
    }
    return used ? (factor - 1) * 100 : null;
  }
}
