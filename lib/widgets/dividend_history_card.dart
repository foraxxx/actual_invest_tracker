import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../services/currency_service.dart';
import '../services/dividend_history_service.dart';
import '../services/dividend_tax_service.dart';
import '../services/moex_service.dart';
import '../services/online_settings_service.dart';
import 'payout_yield_sheet.dart' show yieldPct;
import 'year_bars.dart';

/// Блок «Дивидендная история» в карточке акции: дивиденды на акцию по годам
/// (доходность к вашей цене или рост выплат), ожидаемая выплата и всё, что
/// пришло вам.
class DividendHistoryCard extends StatefulWidget {
  final String ticker;
  final HoldingInfo? holding;

  /// Текущая цена акции, ₽.
  final double? price;

  /// Ваши выплаты по бумаге, от новых к старым.
  final List<Income> incomes;
  final VoidCallback onAdd;
  final ValueChanged<Income> onDelete;

  const DividendHistoryCard({
    super.key,
    required this.ticker,
    required this.holding,
    required this.price,
    required this.incomes,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<DividendHistoryCard> createState() => _DividendHistoryCardState();
}

class _DividendHistoryCardState extends State<DividendHistoryCard> {
  static const _modeKey = 'dividendMode';
  bool _growth = AppearanceService.ui(_modeKey) == 'growth';
  bool _expanded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    DividendHistoryService.version.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    DividendHistoryService.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!OnlineSettingsService.enabled) return;
    _loading = true;
    var moex = const <MoexPayout>[];
    try {
      moex = await MoexService.fetchPayouts(widget.ticker, isBond: false);
    } catch (_) {}
    await DividendHistoryService.update(widget.ticker, moex: moex);
    if (mounted) setState(() => _loading = false);
  }

  void _setMode(bool growth) {
    setState(() => _growth = growth);
    AppearanceService.setUi(_modeKey, growth ? 'growth' : 'yield');
  }

  String _amount(double v) => Fmt.perShare(v);

  @override
  Widget build(BuildContext context) {
    final h = DividendHistoryService.of(widget.ticker);
    final hidden = AppearanceService.amountsHidden;
    final avg = widget.holding?.avgCost;
    final price = widget.price;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Дивидендная история', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('На одну акцию, ₽', style: TextStyle(fontSize: 11, color: context.dim)),
                  ],
                ),
              ),
              _toggle(context),
            ],
          ),
          const SizedBox(height: 10),
          if (h == null || h.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _loading
                    ? 'Загружаем историю дивидендов…'
                    : !OnlineSettingsService.enabled
                        ? 'История дивидендов загружается с сайтов, когда включена загрузка с биржи'
                        : 'История дивидендов не нашлась: компания не платила или сайт не ответил',
                style: TextStyle(fontSize: 12, color: context.dim, height: 1.35),
              ),
            )
          else ...[
            YearBars(bars: _bars(h, avg), format: _amount, selectable: true),
            _legend(context),
            ..._yields(context, h, avg, price),
            if (h.nextAnnounced != null) _expected(context, h.nextAnnounced!, hidden),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: context.dim.withOpacity(0.15)),
          const SizedBox(height: 12),
          _received(context, hidden),
          if (h != null && (h.source.isNotEmpty || h.updatedAt != null)) ...[
            const SizedBox(height: 10),
            Text(_sourceLine(h), style: TextStyle(fontSize: 10.5, color: context.dim)),
          ],
        ],
      ),
    );
  }

  Widget _toggle(BuildContext context) {
    Widget item(String label, bool growth) {
      final on = _growth == growth;
      return GestureDetector(
        onTap: () => _setMode(growth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? context.accent.withOpacity(0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? null : context.dim),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [item('Доходность', false), item('Рост выплат', true)]),
    );
  }

  List<YearBar> _bars(DividendHistory h, double? avg) {
    if (h.records.isEmpty) return const [];
    final byYear = <int, List<DividendRecord>>{};
    for (final r in h.records) {
      (byYear[r.date.year] ??= []).add(r);
    }
    final first = byYear.keys.reduce((a, b) => a < b ? a : b);
    final last = byYear.keys.reduce((a, b) => a > b ? a : b);
    String? yieldOf(double v) => avg != null && avg > 0 && v > 0 ? yieldPct(v / avg * 100) : null;
    final result = <YearBar>[];
    double? prev;
    for (int y = first; y <= last; y++) {
      final list = <DividendRecord>[...?byYear[y]]..sort((a, b) => a.date.compareTo(b.date));
      final parts = [
        for (final r in list)
          BarPart(
            r.amount,
            kind: r.forecast
                ? BarKind.forecast
                : r.isFuture
                    ? BarKind.announced
                    : BarKind.paid,
            selectedTop: yieldOf(r.amount),
            selectedNote: r.forecast ? 'прогноз' : Fmt.dayShort(r.date),
          ),
      ];
      final total = parts.fold(0.0, (s, p) => s + p.value);
      String? top;
      Color? color;
      if (_growth) {
        if (prev != null && prev > 0 && total > 0) {
          final g = (total / prev - 1) * 100;
          top = '${g >= 0 ? '+' : '−'}${Fmt.group(g.abs(), decimals: 0)}%';
          color = g >= 0 ? AppColors.positive : AppColors.negative;
        }
      } else {
        top = yieldOf(total);
        color = AppColors.positive;
      }
      final onlyForecast = parts.isNotEmpty && parts.every((p) => p.kind == BarKind.forecast);
      result.add(YearBar(
        year: y,
        parts: parts,
        top: top,
        topColor: color,
        note: onlyForecast
            ? 'прогноз'
            : parts.any((p) => p.kind == BarKind.announced)
                ? 'объявлено'
                : null,
      ));
      prev = total;
    }
    return result;
  }

  Widget _legend(BuildContext context) {
    Widget item(Widget mark, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [mark, const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 10.5, color: context.dim))],
        );
    Widget box({Color? fill, Border? border, Gradient? gradient}) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: fill, border: border, gradient: gradient, borderRadius: BorderRadius.circular(2)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          item(box(fill: AppColors.info), 'выплачено'),
          item(box(fill: AppColors.info.withOpacity(0.45)), 'объявлено'),
          item(box(border: Border.all(color: AppColors.info.withOpacity(0.6))), 'прогноз'),
        ],
      ),
    );
  }

  List<Widget> _yields(BuildContext context, DividendHistory h, double? avg, double? price) {
    final d = h.last12m;
    if (d <= 0) return const [];
    Widget part(String label, double v, Color? color) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$label '),
            TextSpan(text: yieldPct(v), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          ]),
          style: TextStyle(fontSize: 12, color: context.dim),
        );
    return [
      const SizedBox(height: 6),
      Divider(height: 1, color: context.dim.withOpacity(0.15)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          if (avg != null && avg > 0) part('к средней цене', d / avg * 100, AppColors.positive),
          if (price != null && price > 0) part('к текущей цене', d / price * 100, null),
        ],
      ),
    ];
  }

  Widget _expected(BuildContext context, DividendRecord r, bool hidden) {
    final qty = widget.holding?.qty ?? 0;
    final you = qty * r.amount * 0.87;
    final month = Fmt.dateLong(r.date).split(' ')[1];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: AppRadius.all(AppRadius.sm),
        border: Border.all(color: AppColors.info.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text('${r.date.day}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.05)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(month, style: TextStyle(fontSize: 10, color: context.dim)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.date.year == DateTime.now().year ? 'Ожидается · отсечка' : 'Ожидается · отсечка в ${r.date.year} году',
                  style: TextStyle(fontSize: 11, color: context.dim),
                ),
                const SizedBox(height: 1),
                Text('${_amount(r.amount)} ₽ на акцию', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                if (qty > 0)
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'получено после налога '),
                      TextSpan(
                        text: hidden ? '••• ₽' : '≈ ${Fmt.money(you)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.positive),
                      ),
                    ]),
                    style: TextStyle(fontSize: 12, color: context.dim),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _received(BuildContext context, bool hidden) {
    final incomes = widget.incomes;
    final net = incomes.fold(0.0, (s, i) => s + CurrencyService.toRub(i.amountNet, i.currency, date: i.date));
    // Если брокер не указал налог, сумма до налога считается по дивиденду
    // на акцию и числу акций на дату отсечки.
    var noTax = 0;
    final gross = incomes.fold(0.0, (s, i) {
      var g = i.amountGross;
      if (i.taxPaid <= 0) {
        final info = DividendTaxService.infoFor(i);
        if (info != null && info.gross > g) {
          g = info.gross;
        } else {
          noTax++;
        }
      }
      return s + CurrencyService.toRub(g, i.currency, date: i.date);
    });
    final shown = _expanded ? incomes : incomes.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Получено', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(
                    incomes.isEmpty
                        ? 'Выплаты по этой акции ещё не записаны'
                        : '${incomes.length} ${Fmt.payouts(incomes.length)} · после налога',
                    style: TextStyle(fontSize: 11.5, color: context.dim),
                  ),
                ],
              ),
            ),
            if (incomes.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(hidden ? '••• ₽' : Fmt.money(net), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(
                    hidden
                        ? 'до налога ••• ₽'
                        : noTax == incomes.length
                            ? 'налог брокер не указал'
                            : 'до налога ${noTax > 0 ? '≈ ' : ''}${Fmt.money(gross)}',
                    style: TextStyle(fontSize: 11, color: context.dim),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final i in shown) _incomeRow(context, i, hidden),
        if (!_expanded && incomes.length > 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _expanded = true),
              child: Text('Ещё ${incomes.length - 2} ${Fmt.payouts(incomes.length - 2)} ›'),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Добавить выплату', style: TextStyle(fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 11),
            side: BorderSide(color: context.accent.withOpacity(0.45)),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
          ),
        ),
      ],
    );
  }

  Widget _incomeRow(BuildContext context, Income i, bool hidden) {
    // На акцию — то, что пришло на счёт (после налога), делённое на число
    // акций на дату отсечки. Если отсечки нет в истории — на дату выплаты.
    final info = DividendTaxService.infoFor(i);
    final qty = info != null
        ? info.shares
        : AnalyticsService.holdingsAt(date: DateTime(i.date.year, i.date.month, i.date.day, 23, 59, 59))[i.ticker]?.qty ?? 0;
    final perShare = qty > 0 ? i.amountNet / qty : null;
    return Dismissible(
      key: Key('div-${i.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.negative.withOpacity(0.15),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
      ),
      onDismissed: (_) => widget.onDelete(i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.dim.withOpacity(0.12)))),
        child: Row(
          children: [
            Expanded(child: Text(Fmt.dateLong(i.date), style: const TextStyle(fontSize: 13))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hidden ? '+••• ₽' : '+${Fmt.money(CurrencyService.toRub(i.amountNet, i.currency, date: i.date))}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.positive),
                ),
                if (perShare != null)
                  Text('${Fmt.perShare(perShare, like: info?.record.amount)} ₽ на акцию', style: TextStyle(fontSize: 11, color: context.dim)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLine(DividendHistory h) {
    final src = h.source.isEmpty ? 'сайтов' : h.source;
    final u = h.updatedAt;
    String when = '';
    if (u != null) {
      final now = DateTime.now();
      final days = DateTime(now.year, now.month, now.day).difference(DateTime(u.year, u.month, u.day)).inDays;
      when = days == 0 ? 'сегодня' : days == 1 ? 'вчера' : Fmt.dateLong(u);
    }
    if (h.error != null) {
      return 'История выплат — $src, сохранена на телефоне. '
          '${when.isEmpty ? 'Сайт не ответил' : 'Не обновлялась с $when: сайт не ответил'}';
    }
    return 'История выплат — $src, сохранена на телефоне${when.isEmpty ? '' : ' · обновлено $when'}';
  }
}
