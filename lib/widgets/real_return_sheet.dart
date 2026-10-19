import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/cbr_service.dart';
import '../services/online_settings_service.dart';
import '../services/real_return_service.dart';

const _periods = [
  PeriodFilter.month1,
  PeriodFilter.month3,
  PeriodFilter.month6,
  PeriodFilter.year1,
  PeriodFilter.all,
];

String _tabLabel(PeriodFilter f) => switch (f) {
      PeriodFilter.month1 => '1 мес',
      PeriodFilter.month3 => '3 мес',
      PeriodFilter.month6 => '6 мес',
      PeriodFilter.year1 => 'Год',
      PeriodFilter.all => 'Всё',
    };

String realReturnPeriodText(PeriodFilter f) => switch (f) {
      PeriodFilter.month1 => 'за месяц',
      PeriodFilter.month3 => 'за 3 месяца',
      PeriodFilter.month6 => 'за полгода',
      PeriodFilter.year1 => 'за год',
      PeriodFilter.all => 'за всё время',
    };

const _months = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

/// «+3.4 п.п.» — разница двух процентов.
String formatPoints(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} п.п.';

/// «данные Банка России за сентябрь 2026».
String cbrSourceText() {
  final last = CbrService.lastInflation;
  if (last == null) return 'Инфляция и ключевая ставка — Банк России';
  return 'Инфляция и ключевая ставка — Банк России, данные за ${_months[last.month - 1]} ${last.year}';
}

/// Окно «Против инфляции»: портфель против роста цен и ключевой ставки.
Future<void> showRealReturnSheet(BuildContext context, PeriodFilter initial) {
  var period = initial;
  return showAppSheet(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: CbrService.version,
      builder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final r = RealReturnService.forPeriod(period);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: 'Против инфляции',
                    subtitle: r == null
                        ? realReturnPeriodText(period)
                        : '${realReturnPeriodText(period)} · ${Fmt.date(r.from)} — ${Fmt.date(r.to)}',
                  ),
                  const SizedBox(height: 12),
                  SegmentedToggle<PeriodFilter>(
                    values: _periods,
                    selected: period,
                    labelOf: _tabLabel,
                    onChanged: (f) => setSheet(() => period = f),
                  ),
                  const SizedBox(height: 16),
                  if (r == null) _noData(ctx) else ..._content(ctx, r),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<String?>(
                    valueListenable: CbrService.error,
                    builder: (ctx, error, __) => error == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InfoBanner(
                              text: error,
                              icon: Icons.cloud_off_rounded,
                              color: AppColors.warning,
                              onTap: () => CbrService.refreshIfStale(force: true),
                            ),
                          ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.account_balance_outlined, size: 14, color: ctx.dim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(cbrSourceText(), style: TextStyle(fontSize: 11.5, color: ctx.dim)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _noData(BuildContext ctx) {
  final String text;
  if (!CbrService.hasData && !OnlineSettingsService.enabled) {
    text = 'Чтобы сравнить портфель с инфляцией, включите в настройках загрузку данных из интернета: '
        'инфляцию и ключевую ставку приложение берёт у Банка России.';
  } else if (!CbrService.hasData) {
    text = 'Данные Банка России ещё не загружены. Проверьте интернет и попробуйте ещё раз.';
  } else {
    text = 'За этот период нет своих денег в портфеле — сравнивать не с чем.';
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: ctx.dim)),
      if (!CbrService.hasData && OnlineSettingsService.enabled) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => CbrService.refreshIfStale(force: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Загрузить'),
          ),
        ),
      ],
    ],
  );
}

List<Widget> _content(BuildContext ctx, RealReturn r) {
  final ahead = r.vsInflation >= 0;
  final bars = <(String, double, Color)>[
    ('Портфель', r.portfolioPct, AppColors.pnl(r.portfolioPct)),
    ('Под ключевую ставку', r.keyRatePct, AppColors.info),
    ('Инфляция', r.inflationPct, AppColors.warning),
  ];
  final maxAbs = bars.fold(0.0, (m, b) => math.max(m, b.$2.abs()));

  Widget money(String label, double value, {Color? color, bool bold = false}) {
    final text = Fmt.money(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: bold ? null : ctx.dim))),
          HiddenAmount.forText(
            text,
            fontSize: 13.5,
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  final gainText = Fmt.signedMoney(r.realGainRub);
  final String conclusion;
  if (ahead && r.vsKeyRate >= 0) {
    conclusion = 'Портфель обогнал и рост цен, и ключевую ставку: вложения работают лучше вклада.';
  } else if (ahead) {
    conclusion = 'Портфель обогнал рост цен, но под ключевую ставку деньги выросли бы сильнее. '
        'Короткий период может быть обманчив — посмотрите на год или всё время.';
  } else {
    conclusion = 'Портфель отстал от роста цен: на те же деньги сейчас можно купить меньше, чем в начале периода.';
  }

  return [
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatPoints(r.vsInflation),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.pnl(r.vsInflation)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              ahead ? 'портфель обогнал инфляцию' : 'портфель отстал от инфляции',
              style: TextStyle(fontSize: 12.5, color: ctx.dim),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    for (final b in bars)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(b.$1, style: const TextStyle(fontSize: 13))),
                Text(Fmt.pct(b.$2), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: b.$3)),
              ],
            ),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (ctx, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 8,
                  width: maxAbs <= 0 ? 4 : math.max(4.0, c.maxWidth * b.$2.abs() / maxAbs),
                  decoration: BoxDecoration(
                    color: b.$3.withOpacity(b.$2 < 0 ? 0.45 : 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    const SizedBox(height: 4),
    AppCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      radius: AppRadius.sm,
      child: Column(
        children: [
          money('Своих денег вложено', r.base),
          money('Портфель сейчас', r.portfolio, bold: true),
          money('Те же деньги с учётом роста цен', r.inflation),
          money('Те же деньги под ключевую ставку', r.keyRate),
          Container(height: 1, color: ctx.hairline, margin: const EdgeInsets.symmetric(vertical: 4)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Выигрыш у инфляции', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                HiddenAmount.forText(
                  gainText,
                  fontSize: 14,
                  child: Text(
                    gainText,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pnl(r.realGainRub)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    Text(conclusion, style: const TextStyle(fontSize: 13, height: 1.4)),
    const SizedBox(height: 8),
    Text(
      'Каждое пополнение сравнивается с ростом цен и ключевой ставкой с того дня, когда деньги пришли на счёт. '
      'Ключевая ставка — ориентир для вкладов, реальные ставки банков бывают ниже.',
      style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
    ),
  ];
}
