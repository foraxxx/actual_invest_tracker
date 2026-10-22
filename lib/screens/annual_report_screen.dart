import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../design/charts.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/annual_report_service.dart';
import '../services/portfolio_service.dart';
import '../services/report_pdf_service.dart';
import '../widgets/month_calendar.dart';
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

  @override
  void initState() {
    super.initState();
    _years = AnnualReportService.availableYears();
    _year = _years.first;
  }

  Future<void> _exportPdf(AnnualReport report) async {
    setState(() => _exporting = true);
    try {
      final path = await ReportPdfService.save(
        report,
        portfolioName: PortfolioService.active.name,
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

  @override
  Widget build(BuildContext context) {
    final report = AnnualReportService.build(_year);

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
            onChanged: (y) => setState(() => _year = y),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          FadeSlideIn(child: _summaryCard(report)),

          const SizedBox(height: 14),
          Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Куплено за год',
                    icon: Icons.shopping_bag_outlined,
                    value: report.boughtRub,
                    formatter: (v) => Fmt.money(v),
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Продано за год',
                    icon: Icons.sell_outlined,
                    value: report.soldRub,
                    formatter: (v) => Fmt.money(v),
                    color: AppColors.violet,
                  ),
                ),
              ],
          ),
          const SizedBox(height: 10),
          Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Прибыль от продаж',
                    icon: Icons.price_check_rounded,
                    value: report.realizedRub,
                    formatter: (v) => Fmt.signedMoney(v),
                    color: AppColors.pnl(report.realizedRub),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Удержан налог',
                    icon: Icons.receipt_long_rounded,
                    value: report.taxPaidRub,
                    formatter: (v) => Fmt.money(v),
                    color: AppColors.warning,
                  ),
                ),
              ],
          ),

          // Календари вместо столбиков: суммы видны целиком, а нажатие на
          // месяц показывает каждую выплату или сделку.
          if (report.payoutsByMonth.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionTitle(title: 'Выплаты по месяцам', padding: EdgeInsets.only(bottom: 12)),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: MonthCalendar(months: _payoutMonths(report), color: AppColors.positive),
            ),
          ],

          if (report.trades.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Сделки по месяцам',
              subtitle: 'Вложено в бумаги: покупки минус продажи',
              padding: EdgeInsets.only(bottom: 12),
            ),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: MonthCalendar(months: _tradeMonths(report), color: AppColors.info),
            ),
          ],

          if (report.bySector.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Распределение',
              subtitle: 'По секторам на конец периода',
              padding: EdgeInsets.only(bottom: 12),
            ),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: DonutChart(
                data: report.bySector,
                valueFormatter: (v) => Fmt.money(v),
                centerLabel: 'Всего',
                size: 190,
              ),
            ),
          ],

          if (report.newRows.isNotEmpty) ...[
            const SizedBox(height: 22),
            SectionTitle(
              title: 'Новые бумаги',
              subtitle: 'Куплены впервые в $_year году · ${report.newRows.length}',
              padding: const EdgeInsets.only(bottom: 12),
            ),
            for (int i = 0; i < report.newRows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn.staggered(index: i, child: _row(report.newRows[i])),
              ),
          ],

          if (report.oldRows.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionTitle(
              title: 'Куплены раньше',
              subtitle: 'В портфеле до $_year года · ${report.oldRows.length}',
              padding: const EdgeInsets.only(bottom: 12),
            ),
            for (int i = 0; i < report.oldRows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn.staggered(index: i, child: _row(report.oldRows[i])),
              ),
          ],

          if (report.rows.isEmpty)
            const EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'За этот год данных нет',
              subtitle: 'Выберите другой год — в списке только те, где были сделки или выплаты.',
            ),

          const SizedBox(height: 22),
          GradientButton(
            label: _exporting ? 'Собираю PDF…' : 'Сохранить отчёт в PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: _exporting ? null : () => _exportPdf(report),
          ),
        ],
      ),
    );
  }

  /// Календарь выплат года: только полученное, без прогноза — это итоги.
  List<CalendarMonth> _payoutMonths(AnnualReport report) => [
        for (int m = 1; m <= 12; m++)
          () {
            final events = report.payoutEvents.where((e) => e.date.month == m).toList();
            final total = report.payoutsByMonth[m] ?? 0;
            return CalendarMonth(
              month: DateTime(report.year, m),
              value: total,
              main: total <= 0 ? '—' : Fmt.money(total),
              summary: events.isEmpty ? '' : '${events.length} ${Fmt.payouts(events.length)}',
              lines: [
                for (final e in events)
                  CalendarLine(date: e.date, title: e.name, amount: Fmt.money(e.rub), ticker: e.ticker),
              ],
            );
          }(),
      ];

  /// Календарь сделок: крупно — сколько вложено за месяц (покупки − продажи),
  /// мелко — из чего сложилось. Месяц, где продано больше, чем куплено,
  /// получается со знаком «−» и другим цветом.
  List<CalendarMonth> _tradeMonths(AnnualReport report) => [
        for (int m = 1; m <= 12; m++)
          () {
            final bought = report.boughtByMonth[m] ?? 0;
            final sold = report.soldByMonth[m] ?? 0;
            final net = bought - sold;
            final events = report.trades.where((e) => e.date.month == m).toList();
            return CalendarMonth(
              month: DateTime(report.year, m),
              value: net,
              main: events.isEmpty ? '—' : Fmt.signedMoney(net),
              captions: [
                if (bought > 0) ('куплено ${Fmt.money(bought)}', null),
                if (sold > 0) ('продано ${Fmt.money(sold)}', AppColors.negative),
              ],
              summary: events.isEmpty ? '' : '${events.length} ${Fmt.deals(events.length)}',
              lines: [
                for (final e in events)
                  CalendarLine(
                    date: e.date,
                    title: '${e.isSell ? 'Продажа' : 'Покупка'} · ${e.name}',
                    amount: Fmt.money(e.rub),
                    amountColor: e.isSell ? AppColors.negative : null,
                    ticker: e.ticker,
                  ),
              ],
            );
          }(),
      ];

  Widget _summaryCard(AnnualReport report) {
    final result = report.totalResultRub;
    return GlassCard(
      glow: AppColors.pnl(result),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Итог ${report.year} года',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
          ),
          const SizedBox(height: 8),
          RollingNumber(
            value: result,
            formatter: (v) => Fmt.signedMoney(v),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.3,
              color: AppColors.pnl(result),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Выплаты ${Fmt.money(report.payoutsRub)} · продажи ${Fmt.signedMoney(report.realizedRub)}',
            style: TextStyle(fontSize: 11.5, color: context.dim),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _miniStat('Вложено за год', Fmt.money(report.investedRub))),
              Container(width: 1, height: 30, color: context.hairline),
              Expanded(child: _miniStat('Стоимость бумаг', Fmt.money(report.valueEndRub))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.dim),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
      ],
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
                        if (r.isClosed) ...[
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
