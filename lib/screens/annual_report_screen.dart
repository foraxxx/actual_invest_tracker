import 'package:flutter/material.dart';
import '../widgets/tax_widgets.dart';
import '../services/tax_service.dart';
import 'package:share_plus/share_plus.dart';

import '../design/charts.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/annual_report_service.dart';
import '../services/portfolio_service.dart';
import '../services/report_pdf_service.dart';
import '../services/cbr_service.dart';
import '../services/moex_service.dart';
import '../services/storage_service.dart';
import '../models/plan.dart';
import '../widgets/ticker_avatar.dart';
import 'ticker_detail_screen.dart';

/// Итоги выбранного года: что покупалось, что принесло выплаты, чем
/// закончилась каждая бумага. Отчёт можно выгрузить в PDF.
class AnnualReportScreen extends StatefulWidget {
  const AnnualReportScreen({super.key});

  @override
  State<AnnualReportScreen> createState() => _AnnualReportScreenState();
}

class _AnnualReportScreenState extends State<AnnualReportScreen> {
  late int _year;
  late List<int> _years;
  bool _exporting = false;

  /// Фильтр карточек бумаг: все, новые, раньше, закрытые.
  int _rowsFilter = 0;

  /// Графики пополнений и выплат: по месяцам или нарастающим итогом.
  bool _cumDeposits = false;
  bool _cumPayouts = false;

  /// Рост индекса Мосбиржи за год — загружается с биржи.
  final Map<int, double?> _imoex = {};

  @override
  void initState() {
    super.initState();
    _years = AnnualReportService.availableYears();
    _year = _years.first;
  }

  Future<void> _exportPdf(AnnualReport report) async {
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final months = report.year == now.year ? now.month : 12;
      final keyRate = CbrService.averageKeyRate(
        DateTime(report.year),
        report.year == now.year ? now : DateTime(report.year, 12, 31),
      );
      final path = await ReportPdfService.save(
        report,
        portfolioName: PortfolioService.active.name,
        imoexPct: _imoex[report.year],
        inflationPct: CbrService.inflationIn(DateTime(report.year, 12)) ?? CbrService.inflationIn(DateTime(report.year, months)),
        keyRatePct: keyRate == null ? null : keyRate * months / 12,
      );
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)], subject: 'Итоги ${report.year}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось собрать PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }


  static const _monthsShort = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  static const _monthsNom = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  Future<void> _loadImoex(int year) async {
    if (_imoex.containsKey(year)) return;
    _imoex[year] = null;
    try {
      final now = DateTime.now();
      final pts = await MoexService.fetchCandles(
        engine: 'stock',
        market: 'index',
        secId: 'IMOEX',
        from: DateTime(year - 1, 12, 20),
        till: year == now.year ? now : DateTime(year, 12, 31),
        interval: 24,
        maxRows: 1000,
      );
      final before = pts.where((p) => p.key.year < year).toList();
      final inYear = pts.where((p) => p.key.year == year).toList();
      if (inYear.isEmpty) return;
      final start = before.isNotEmpty ? before.last.value : inYear.first.value;
      if (start > 0 && mounted) setState(() => _imoex[year] = (inYear.last.value / start - 1) * 100);
    } catch (_) {}
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)}) =>
      Padding(padding: const EdgeInsets.only(top: 12), child: AppCard(padding: padding, child: child));

  Widget _title(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing,
          ],
        ),
      );

  /// Налоги за год: что удержано, что удержат, и сколько сэкономил ИИС.
  Widget _taxesBlock(YearTaxes t) {
    final rate = '${(TaxService.rate * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Налоги за $_year'),
        if (t.dividends > 0.5) _line('С дивидендов — удержано', Fmt.money(t.dividends)),
        if (t.coupons > 0.5)
          _line(
            t.deferred ? 'С купонов — при закрытии ИИС' : 'С купонов — брокер удержит',
            '≈ ${Fmt.money(t.coupons)}',
            color: t.deferred ? context.dim : null,
          ),
        if (t.sales > 0.5)
          _line(t.deferred ? 'С продаж — при закрытии ИИС' : 'С продаж', '≈ ${Fmt.money(t.sales)}',
              color: t.deferred ? context.dim : null),
        _line('Итого за год', '≈ ${Fmt.money(t.total)}', color: AppColors.negative, bold: true, divider: true),
        if (t.saved > 0.5) ...[
          const SizedBox(height: 8),
          TaxNote(
            color: AppColors.positive,
            text: 'ИИС сэкономил ≈ ${Fmt.money(t.saved)} налога в этом году — если закрыть счёт после минимального срока.',
          ),
        ],
        const SizedBox(height: 6),
        Text('Ставка $rate — из настроек налога. С купонов и продаж — оценка.',
            style: TextStyle(fontSize: 11, color: context.dim)),
      ],
    );
  }

  Widget _line(String label, String value, {Color? color, bool bold = false, bool divider = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: divider ? BoxDecoration(border: Border(top: BorderSide(color: context.hairline))) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: bold ? 14.5 : 13.5, color: bold ? null : context.dim)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: bold ? 14.5 : 13.5, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
      );

  Widget _tile(String label, String value, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: AppRadius.all(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 2, style: TextStyle(fontSize: 11.5, color: context.dim)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        ),
      );

  /// Линия по 12 месяцам: по месяцам или нарастающим итогом.
  Widget _monthLine(String title, Map<int, double> byMonth, Color color, bool cumulative, VoidCallback onSwitch) {
    final total = byMonth.values.fold(0.0, (a, b) => a + b);
    final lastMonth = _year == DateTime.now().year ? DateTime.now().month : 12;
    final values = <double>[];
    var acc = 0.0;
    for (var m = 1; m <= lastMonth; m++) {
      acc += byMonth[m] ?? 0;
      values.add(cumulative ? acc : (byMonth[m] ?? 0));
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(title,
              trailing: Text('+${Fmt.money(total)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color))),
          if (values.length >= 2)
            Sparkline(
              values: values,
              color: color,
              height: 110,
              tooltipBuilder: (i, v) => '${_monthsNom[i]}\n${Fmt.money(v)}',
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Пока мало месяцев для графика', style: TextStyle(fontSize: 12, color: context.dim)),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var m = 1; m <= lastMonth; m++)
                Text(_monthsShort[m - 1][0].toUpperCase(), style: TextStyle(fontSize: 10, color: context.dim)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: onSwitch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cumulative ? 'нарастающим итогом ⇄ по месяцам' : 'по месяцам ⇄ нарастающим итогом',
                  style: TextStyle(fontSize: 11.5, color: context.dim),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankList(String title, List<(String, String, String, Color?)> items) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(title),
            for (final (ticker, name, value, color) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    TickerAvatar(ticker: ticker, size: 28, glow: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final report = AnnualReportService.build(_year);
    _loadImoex(_year);
    final result = report.totalResultRub;
    final from = DateTime(_year);
    final to = _year == DateTime.now().year ? DateTime.now() : DateTime(_year, 12, 31);

    // Бумаги по результату за год.
    final ranked = report.rows.where((r) => r.valueStartRub + r.boughtSumRub > 0).toList()
      ..sort((a, b) => b.yieldPct.compareTo(a.yieldPct));
    final best = ranked.where((r) => r.yieldPct > 0).take(3).toList();
    final worst = ranked.reversed.where((r) => r.yieldPct < 0).take(3).toList();
    final topPayouts = report.payoutEvents.toList()..sort((a, b) => b.rub.compareTo(a.rub));

    // Пассивный доход.
    final months = _year == DateTime.now().year ? DateTime.now().month : 12;
    final prev = AnnualReportService.availableYears().contains(_year - 1) ? AnnualReportService.build(_year - 1) : null;
    final payoutGrowth = prev == null || prev.payoutsRub <= 0 ? null : (report.payoutsRub / prev.payoutsRub - 1) * 100;
    final byTickerPayouts = <String, double>{};
    for (final e in report.payoutEvents) {
      byTickerPayouts[e.ticker] = (byTickerPayouts[e.ticker] ?? 0) + e.rub;
    }
    final topPayer = byTickerPayouts.entries.isEmpty
        ? null
        : (byTickerPayouts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
    String nameOf(String t) =>
        report.rows.firstWhere((r) => r.ticker == t, orElse: () => report.rows.first).name;

    // Состав.
    final held = report.rows.where((r) => r.valueRub > 0).toList()..sort((a, b) => b.valueRub.compareTo(a.valueRub));
    final heldStart = report.rows.where((r) => r.valueStartRub > 0).length;
    final top5 = held.take(5).fold(0.0, (s, r) => s + r.valueRub);
    double drawdown = 0;
    DateTime? ddDate;
    var peak = 0.0;
    for (final p in report.valueSeries) {
      if (p.value > peak) peak = p.value;
      if (peak > 0) {
        final d = (p.value / peak - 1) * 100;
        if (d < drawdown) {
          drawdown = d;
          ddDate = p.key;
        }
      }
    }
    MapEntry<DateTime, double>? maxPoint;
    for (final p in report.valueSeries) {
      if (maxPoint == null || p.value > maxPoint.value) maxPoint = p;
    }

    // Самый доходный месяц — по стоимости на конец месяцев.
    String? bestMonth;
    {
      double bestPct = -1e9;
      for (var m = 1; m <= months; m++) {
        final inM = report.valueSeries.where((p) => p.key.month == m).toList();
        final before = report.valueSeries.where((p) => p.key.month < m).toList();
        if (inM.isEmpty) continue;
        final start = before.isNotEmpty ? before.last.value : inM.first.value;
        if (start <= 0) continue;
        final dep = report.depositsByMonth[m] ?? 0;
        final pct = (inM.last.value - dep - start) / start * 100;
        if (pct > bestPct) {
          bestPct = pct;
          bestMonth = '${_monthsNom[m - 1]} · ${Fmt.pct(pct)}';
        }
      }
    }
    final biggestBuy = report.trades.where((e) => !e.isSell).fold<ReportEvent?>(
        null, (a, b) => a == null || b.rub > a.rub ? b : a);

    // Планы.
    final yearPlans = StorageService.plans
        .where((p) => p.targetDate != null && p.targetDate!.year == _year)
        .toList();
    final donePlans = yearPlans.where((p) => p.status == PlanStatus.done).length;
    final monthsWithDeposit = report.depositsByMonth.values.where((v) => v > 0).length;

    final inflation = CbrService.inflationIn(DateTime(_year, 12)) ?? CbrService.inflationIn(DateTime(_year, months));
    final keyRate = CbrService.averageKeyRate(from, to);
    final imoex = _imoex[_year];

    final rows = switch (_rowsFilter) {
      1 => report.newRows,
      2 => report.oldRows,
      3 => report.rows.where((r) => r.isClosed || r.redeemed).toList(),
      _ => report.rows,
    };
    final closedCount = report.rows.where((r) => r.isClosed || r.redeemed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Итоги года'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Сохранить PDF',
            onPressed: _exporting ? null : () => _exportPdf(report),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          PillTabs<int>(
            values: _years,
            selected: _year,
            labelOf: (y) => '$y',
            onChanged: (y) => setState(() {
              _year = y;
              _rowsFilter = 0;
            }),
            padding: EdgeInsets.zero,
          ),
          if (report.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.event_busy_rounded,
                title: 'За этот год данных нет',
                subtitle: 'Выберите другой год — в списке только те, где были сделки или выплаты.',
              ),
            )
          else ...[
            // --- Итог ---
            _card(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Портфель за $_year год', style: TextStyle(fontSize: 12.5, color: context.dim)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.signedMoney(result),
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.pnl(result)),
                    ),
                  ),
                  Text('${Fmt.pct(report.yieldPct)} · с учётом выплат',
                      style: TextStyle(fontSize: 13, color: context.dim)),
                  const SizedBox(height: 10),
                  Text('${Fmt.money(report.valueStartRub)}  →  ${Fmt.money(report.valueEndRub)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              _tile('Вложено за год', Fmt.signedMoney(report.investedRub)),
              const SizedBox(width: 8),
              _tile('Выплаты', '+${Fmt.money(report.payoutsRub)}', color: AppColors.positive),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _tile('Прибыль от продаж', Fmt.signedMoney(report.realizedRub), color: AppColors.pnl(report.realizedRub)),
              const SizedBox(width: 8),
              _tile('Налог', Fmt.money(report.taxPaidRub)),
            ]),

            // --- Стоимость за год ---
            if (report.valueSeries.length >= 2)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title('Стоимость за год'),
                    Sparkline(
                      values: report.valueSeries.map((e) => e.value).toList(),
                      color: AppColors.pnl(result),
                      height: 130,
                      tooltipBuilder: (i, v) => '${Fmt.date(report.valueSeries[i].key)}\n${Fmt.money(v)}',
                    ),
                  ],
                ),
              ),

            _monthLine('Пополнения по месяцам', report.depositsByMonth, AppColors.violet, _cumDeposits,
                () => setState(() => _cumDeposits = !_cumDeposits)),
            _monthLine('Выплаты по месяцам', report.payoutsByMonth, AppColors.positive, _cumPayouts,
                () => setState(() => _cumPayouts = !_cumPayouts)),

            // --- Из чего сложился год ---
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Из чего сложился год'),
                  _line('На 1 января', Fmt.money(report.valueStartRub)),
                  _line('Куплено бумаг', '+${Fmt.money(report.boughtRub)}'),
                  _line('Продано бумаг', '−${Fmt.money(report.soldRub)}'),
                  _line('Рост цен', Fmt.signedMoney(report.valueEndRub - report.valueStartRub - report.boughtRub + report.soldRub),
                      color: AppColors.pnl(report.valueEndRub - report.valueStartRub - report.boughtRub + report.soldRub)),
                  _line('Выплаты', '+${Fmt.money(report.payoutsRub)}', color: AppColors.positive),
                  _line('Налоги и комиссии', '−${Fmt.money(report.taxPaidRub + report.feesRub)}', color: AppColors.negative),
                  _line('На ${_year == DateTime.now().year ? 'сегодня' : '31 декабря'}', Fmt.money(report.valueEndRub),
                      bold: true, divider: true),
                ],
              ),
            ),

            // --- Налоги за год ---
            if (report.taxes != null && (report.taxes!.dividends + report.taxes!.coupons + report.taxes!.sales) > 0.5)
              _card(child: _taxesBlock(report.taxes!)),

            // --- Доходность в сравнении ---
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Доходность за год'),
                  _line('Мой портфель', Fmt.pct(report.yieldPct), color: AppColors.pnl(report.yieldPct), bold: true),
                  _line('Индекс Мосбиржи', imoex == null ? 'загружается…' : Fmt.pct(imoex)),
                  if (inflation != null) _line('Инфляция', Fmt.pct(inflation)),
                  if (keyRate != null) _line('Вклад под ключевую ставку', '≈ ${Fmt.pct(keyRate * months / 12)}'),
                ],
              ),
            ),

            if (best.isNotEmpty)
              _rankList('Лучшие бумаги', [
                for (final r in best) (r.ticker, r.name, Fmt.pct(r.yieldPct), AppColors.positive),
              ]),
            if (worst.isNotEmpty)
              _rankList('Отстающие бумаги', [
                for (final r in worst) (r.ticker, r.name, Fmt.pct(r.yieldPct), AppColors.negative),
              ]),
            if (topPayouts.isNotEmpty)
              _rankList('Крупнейшие выплаты', [
                for (final e in topPayouts.take(3))
                  (e.ticker, '${e.name} · ${_monthsShort[e.date.month - 1]}', Fmt.money(e.rub), null),
              ]),

            // --- Пассивный доход ---
            if (report.payoutsRub > 0)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title('Пассивный доход'),
                    _line('В среднем в месяц', Fmt.money(report.payoutsRub / months)),
                    if (payoutGrowth != null)
                      _line('К ${_year - 1} году', Fmt.pct(payoutGrowth), color: AppColors.pnl(payoutGrowth)),
                    if (report.valueEndRub > 0)
                      _line('Доходность выплат', '${Fmt.pct(report.payoutsRub / report.valueEndRub * 100 * 12 / months)} годовых'),
                    if (topPayer != null)
                      _line('Больше всего дала',
                          '${nameOf(topPayer.key)} · ${(topPayer.value / report.payoutsRub * 100).round()}%'),
                  ],
                ),
              ),

            // --- Состав и риск ---
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Состав и риск'),
                  _line('Бумаг в портфеле', '${held.length} (было $heldStart)'),
                  if (held.isNotEmpty && report.valueEndRub > 0)
                    _line('Крупнейшая доля',
                        '${held.first.name} · ${(held.first.valueRub / report.valueEndRub * 100).round()}%'),
                  if (held.length > 5 && report.valueEndRub > 0)
                    _line('Топ-5 бумаг', '${(top5 / report.valueEndRub * 100).round()}% портфеля'),
                  if (ddDate != null && drawdown < -0.5)
                    _line('Самая большая просадка', '${Fmt.pct(drawdown)} · ${_monthsShort[ddDate.month - 1]}',
                        color: AppColors.negative),
                ],
              ),
            ),

            // --- Сделки года ---
            if (report.trades.isNotEmpty)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title('Сделки года'),
                    _line('Куплено', Fmt.money(report.boughtRub)),
                    _line('Продано', Fmt.money(report.soldRub)),
                    _line('Сделок', '${report.trades.length}'),
                    if (report.trades.any((e) => !e.isSell))
                      _line('Средняя покупка',
                          Fmt.money(report.boughtRub / report.trades.where((e) => !e.isSell).length)),
                    _line('Комиссии', Fmt.money(report.feesRub)),
                  ],
                ),
              ),

            // --- Рекорды ---
            if (maxPoint != null || bestMonth != null || biggestBuy != null)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title('Рекорды года'),
                    if (maxPoint != null)
                      _line('Максимум портфеля', '${Fmt.money(maxPoint.value)} · ${Fmt.dayShort(maxPoint.key)}'),
                    if (bestMonth != null) _line('Самый доходный месяц', bestMonth),
                    if (biggestBuy != null)
                      _line('Самая крупная покупка', '${biggestBuy.name} · ${Fmt.money(biggestBuy.rub)}'),
                  ],
                ),
              ),

            // --- Планы и привычки ---
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _title('Планы и привычки'),
                  if (yearPlans.isNotEmpty) _line('Планов выполнено', '$donePlans из ${yearPlans.length}'),
                  _line('Месяцев с пополнением', '$monthsWithDeposit из $months'),
                  if (prev != null && prev.investedRub > 0)
                    _line('Вложено к ${_year - 1} году', Fmt.pct((report.investedRub / prev.investedRub - 1) * 100)),
                ],
              ),
            ),

            // --- Секторы ---
            if (report.bySector.isNotEmpty) _sectorsCard(report.bySector),

            // --- Бумаги года ---
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Text('Бумаги года', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                Text('${report.rows.length}', style: TextStyle(fontSize: 13, color: context.dim)),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, label) in [
                    (0, 'Все ${report.rows.length}'),
                    (1, 'Новые ${report.newRows.length}'),
                    (2, 'Раньше ${report.oldRows.length}'),
                    if (closedCount > 0) (3, 'Закрытые $closedCount'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pressable(
                        onTap: () => setState(() => _rowsFilter = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _rowsFilter == i
                                ? (context.isDark ? Colors.white : const Color(0xFF111318))
                                : (context.isDark ? AppColors.darkSurface : AppColors.lightSurfaceHigh),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _rowsFilter == i
                                  ? (context.isDark ? const Color(0xFF111318) : Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn.staggered(index: i, child: _row(rows[i])),
              ),
          ],
        ],
      ),
    );
  }

  /// Секторы одной полосой и подписи с долями.
  Widget _sectorsCard(Map<String, double> bySector) {
    final total = bySector.values.fold(0.0, (a, b) => a + b);
    final entries = bySector.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const palette = [
      AppColors.violet,
      AppColors.warning,
      AppColors.positive,
      AppColors.info,
      AppColors.cyan,
      AppColors.gold,
      AppColors.negative,
    ];
    Color colorOf(int i) => i < palette.length ? palette[i] : AppColors.neutral;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Секторы на конец года'),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (int i = 0; i < entries.length; i++)
                    Expanded(
                      flex: (entries[i].value / total * 1000).round().clamp(1, 1000),
                      child: Container(color: colorOf(i)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (int i = 0; i < entries.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: colorOf(i), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('${entries[i].key} ${(entries[i].value / total * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: context.dim)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(ReportRow r) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.push(
        context,
        AppPageRoute(builder: (_) => TickerDetailScreen(ticker: r.ticker)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              TickerAvatar(ticker: r.ticker, size: 36, glow: false),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.name.trim().isEmpty ? r.ticker : r.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        if (r.redeemed) ...[
                          const SizedBox(width: 6),
                          const TagChip(text: 'погашена', color: AppColors.neutral, fontSize: 9),
                        ] else if (r.isClosed) ...[
                          const SizedBox(width: 6),
                          const TagChip(text: 'закрыта', color: AppColors.neutral, fontSize: 9),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.isClosed ? r.sector : '${Fmt.qty(r.qtyEnd)} шт · ${r.sector}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: context.dim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.valueRub > 0 ? Fmt.money(r.valueRub) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  TagChip(
                    text: Fmt.signedMoney(r.totalResultRub),
                    color: AppColors.pnl(r.totalResultRub),
                    fontSize: 10,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cell('Куплено', r.boughtSumRub > 0 ? Fmt.compact(r.boughtSumRub) : '—'),
              _cell('Продано', r.soldSumRub > 0 ? Fmt.compact(r.soldSumRub) : '—'),
              _cell(
                'Выплаты',
                r.payoutsRub > 0 ? Fmt.compact(r.payoutsRub) : '—',
                color: r.payoutsRub > 0 ? AppColors.positive : null,
              ),
              _cell(
                'Продажи',
                r.realizedRub != 0 ? Fmt.compact(r.realizedRub) : '—',
                color: r.realizedRub == 0 ? null : AppColors.pnl(r.realizedRub),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: context.dim)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
