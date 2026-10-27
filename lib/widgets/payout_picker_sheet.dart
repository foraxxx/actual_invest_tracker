import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../models/purchase.dart';
import '../screens/ticker_detail_screen.dart';
import '../services/favorites_service.dart';
import '../services/payout_picker_service.dart';
import '../services/storage_service.dart';
import 'ticker_avatar.dart';

const monthNamesNom = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

/// «в январе», «в мае».
const monthNamesIn = [
  'январе', 'феврале', 'марте', 'апреле', 'мае', 'июне',
  'июле', 'августе', 'сентябре', 'октябре', 'ноябре', 'декабре',
];

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

enum _Filter { inMonth, monthly, ofz, corp }

/// Подбор бумаг с выплатами в месяце [month]: облигации по графику биржи и
/// акции по вашей истории дивидендов. [deficit] — сколько не хватает до цели.
Future<void> showPayoutPickerSheet(
  BuildContext context, {
  required DateTime month,
  required double deficit,
  bool monthlyOnly = false,
}) {
  var tab = 0; // 0 — облигации, 1 — акции
  // Из цели «докупить» — сразу облигации с ежемесячным купоном.
  var filter = monthlyOnly ? _Filter.monthly : _Filter.inMonth;
  final bondsFuture = PayoutPickerService.bondsFor(month);
  final stocks = PayoutPickerService.stocksFor(month);
  final monthIn = monthNamesIn[month.month - 1];

  return showAppSheet(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: FavoritesService.version,
      builder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              SheetHeader(
                title: monthlyOnly ? 'Выплаты каждый месяц' : 'Выплаты в $monthIn',
                subtitle: deficit > 0.5
                    ? 'не хватает ${Fmt.money(deficit)}${monthlyOnly ? ' в месяц' : ''}'
                    : 'до цели хватает — можно добавить запас',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 12),
              SegmentedToggle<int>(
                values: const [0, 1],
                selected: tab,
                labelOf: (i) => i == 0 ? 'Облигации' : 'Акции',
                onChanged: (i) => setSheet(() => tab = i),
              ),
              const SizedBox(height: 10),
              if (tab == 0)
                ..._bondsTab(ctx, bondsFuture, filter, (f) => setSheet(() => filter = f), month, deficit)
              else
                ..._stocksTab(ctx, stocks, month),
              const SizedBox(height: 10),
              Text(
                'Подбор — не рекомендация купить. Данные облигаций — с Мосбиржи на момент открытия. '
                'Купоны — полной суммой, как приходят; дивиденды — после налога.',
                style: TextStyle(fontSize: 10.5, height: 1.4, color: ctx.dim),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

List<Widget> _bondsTab(
  BuildContext ctx,
  Future<List<BondPick>> future,
  _Filter filter,
  ValueChanged<_Filter> onFilter,
  DateTime month,
  double deficit,
) {
  const labels = {
    _Filter.inMonth: 'Купон в этом месяце',
    _Filter.monthly: 'Ежемесячный купон',
    _Filter.ofz: 'ОФЗ',
    _Filter.corp: 'Корпоративные',
  };
  return [
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in _Filter.values)
          ChoiceChip(
            label: Text(labels[f]!),
            selected: filter == f,
            onSelected: (_) => onFilter(f),
          ),
      ],
    ),
    const SizedBox(height: 10),
    FutureBuilder<List<BondPick>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return InfoBanner(
            icon: Icons.wifi_off_rounded,
            color: AppColors.warning,
            text: 'Не удалось загрузить облигации с биржи. Проверьте интернет и откройте подбор ещё раз.',
          );
        }
        final all = snap.data ?? const <BondPick>[];
        final list = all
            .where((b) => switch (filter) {
                  _Filter.inMonth => true,
                  _Filter.monthly => b.monthly,
                  _Filter.ofz => b.ofz,
                  _Filter.corp => !b.ofz,
                })
            .take(30)
            .toList();
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('Подходящих облигаций не нашлось', style: TextStyle(fontSize: 13, color: ctx.dim)),
          );
        }
        // Сколько вложить, чтобы закрыть месяц, — по первой надёжной бумаге.
        final best = list.firstWhere((b) => !b.risky, orElse: () => list.first);
        final closeAll = deficit > 0.5 && best.coupon > 0 ? (deficit / best.coupon).ceil() * best.price : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final b in list) _BondRow(b: b, month: month),
            if (closeAll != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ctx.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Закрыть ${monthNamesNom[month.month - 1]} полностью: ≈${Fmt.money(closeAll)} в облигации вроде '
                  '«${best.name}». Облигации с ежемесячным купоном добавляют понемногу в каждый месяц.',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
          ],
        );
      },
    ),
  ];
}

List<Widget> _stocksTab(BuildContext ctx, List<StockPick> stocks, DateTime month) {
  final monthIn = monthNamesIn[month.month - 1];
  return [
    Text(
      'Акции, по которым вы получали дивиденды в $monthIn. Сумма — как в прошлый раз на одну акцию; '
      'в этом году может отличаться.',
      style: TextStyle(fontSize: 11.5, height: 1.4, color: ctx.dim),
    ),
    const SizedBox(height: 10),
    if (stocks.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Вы ещё не получали дивиденды в $monthIn', style: TextStyle(fontSize: 13, color: ctx.dim)),
      ),
    for (final s in stocks) _StockRow(s: s, month: month),
  ];
}

class _PickRow extends StatelessWidget {
  final String ticker;
  final String title;
  final String subtitle;
  final String? tag;
  final Color tagColor;
  final String? calc;
  final String? warning;
  final VoidCallback? onPlan;

  const _PickRow({
    required this.ticker,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.tagColor,
    required this.calc,
    this.warning,
    this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final fav = FavoritesService.isFavorite(ticker);
    return Pressable(
      onTap: () => Navigator.push(context, AppPageRoute(builder: (_) => TickerDetailScreen(ticker: ticker))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TickerAvatar(ticker: ticker, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 11.5, color: context.dim)),
                    ],
                  ),
                ),
                if (tag != null) TagChip(text: tag!, color: tagColor, fontSize: 10.5),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: fav ? 'Убрать из избранного' : 'В избранное',
                  icon: Icon(
                    fav ? Icons.star_rounded : Icons.star_border_rounded,
                    color: fav ? AppColors.gold : context.dim,
                    size: 22,
                  ),
                  onPressed: () => FavoritesService.toggle(ticker),
                ),
              ],
            ),
            if (warning != null) ...[
              const SizedBox(height: 6),
              Text(warning!, style: const TextStyle(fontSize: 11, color: AppColors.warning)),
            ],
            if (calc != null || onPlan != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: HiddenAmount.forText(
                      calc ?? '',
                      fontSize: 12,
                      child: Text(calc ?? '', style: TextStyle(fontSize: 12, color: context.dim)),
                    ),
                  ),
                  if (onPlan != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onPlan,
                        child: const Text('+ В план', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BondRow extends StatelessWidget {
  final BondPick b;
  final DateTime month;

  const _BondRow({required this.b, required this.month});

  @override
  Widget build(BuildContext context) {
    final qty = PayoutPickerService.sampleQty(b.price);
    final monthIn = monthNamesIn[month.month - 1];
    final kind = b.monthly ? 'ежемесячно' : '${b.couponDate.day} ${Fmt.dateLong(b.couponDate).split(' ')[1]}';
    final subtitle = 'купон ${Fmt.price(b.coupon, type: AssetType.stock)} ₽ · $kind'
        '${b.maturity == null ? '' : ' · до ${b.maturity!.year}'}'
        '${b.listLevel == null ? '' : ' · уровень ${b.listLevel}'}';
    return _PickRow(
      ticker: b.secid,
      title: b.name,
      subtitle: subtitle,
      tag: b.yieldPct == null ? null : '${b.yieldPct!.toStringAsFixed(1).replaceAll('.', ',')}%',
      tagColor: b.risky ? AppColors.warning : AppColors.positive,
      warning: b.risky ? 'Доходность заметно выше ОФЗ или низкий уровень листинга — повышенный риск' : null,
      calc: '$qty шт ≈ ${Fmt.money(qty * b.price)} → +${Fmt.money(qty * b.coupon)} в $monthIn',
      onPlan: () => _showPlanSheet(
        context,
        ticker: b.secid,
        name: b.name,
        type: AssetType.bond,
        qty: qty,
        price: b.price,
        // Купить нужно до даты фиксации — за рабочий день до купона.
        buyBy: b.couponDate.subtract(const Duration(days: 2)),
        perUnitNet: b.coupon,
        payDate: b.couponDate,
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final StockPick s;
  final DateTime month;

  const _StockRow({required this.s, required this.month});

  @override
  Widget build(BuildContext context) {
    final price = s.price;
    final qty = price == null ? null : PayoutPickerService.sampleQty(price);
    final monthIn = monthNamesIn[month.month - 1];
    final owned = s.qtyNow > 0 ? 'у вас ${Fmt.qty(s.qtyNow)} шт' : 'сейчас нет в портфеле';
    return _PickRow(
      ticker: s.ticker,
      title: s.name,
      subtitle: '${Fmt.date(s.lastDate)} · ${Fmt.price(s.perShare, type: AssetType.stock)} ₽ на акцию · $owned',
      tag: s.payoutPct == null ? null : '${s.payoutPct!.toStringAsFixed(1).replaceAll('.', ',')}%',
      tagColor: AppColors.info,
      calc: qty == null || price == null
          ? null
          : '${s.qtyNow > 0 ? '+' : ''}$qty шт ≈ ${Fmt.money(qty * price)} → ≈+${Fmt.money(qty * s.perShare)} в $monthIn',
      onPlan: price == null
          ? null
          : () => _showPlanSheet(
                context,
                ticker: s.ticker,
                name: s.name,
                type: AssetType.stock,
                qty: qty!,
                price: price,
                buyBy: null,
                perUnitNet: s.perShare,
                payDate: null,
              ),
    );
  }
}

/// «+ В план»: тот же план покупки, что на вкладке «Планы», но заполненный.
Future<void> _showPlanSheet(
  BuildContext context, {
  required String ticker,
  required String name,
  required AssetType type,
  required int qty,
  required double price,
  required DateTime? buyBy,
  required double perUnitNet,
  required DateTime? payDate,
}) {
  final qtyCtrl = TextEditingController(text: '$qty');
  final priceCtrl = TextEditingController(text: Fmt.priceInput(price, type: type));
  DateTime? date = buyBy != null && buyBy.isAfter(DateTime.now()) ? buyBy : null;
  String? error;

  return showAppSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
        final p = double.tryParse(priceCtrl.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Новый план',
                subtitle: payDate == null ? name : '$name · выплата ${Fmt.date(payDate)}',
                trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: qtyCtrl,
                label: 'Сколько купить, шт',
                number: true,
                integerOnly: true,
                onChanged: (_) => setSheet(() => error = null),
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: priceCtrl,
                label: 'По цене до, ₽',
                number: true,
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 10),
              AppDateField(
                value: date,
                label: 'Купить до',
                emptyLabel: 'Без срока',
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                onPicked: (d) => setSheet(() => date = d),
              ),
              if (payDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Чтобы получить выплату, купить нужно до даты фиксации — за рабочий день до ${Fmt.date(payDate)}',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: ctx.dim),
                ),
              ],
              if (q > 0 && p > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.positive.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '≈${Fmt.money(q * p)} → +${Fmt.money(q * perUnitNet)} выплатой на счёт',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: 'Добавить план',
                icon: Icons.add_rounded,
                onPressed: () async {
                  if (q <= 0) {
                    setSheet(() => error = 'Укажите количество');
                    return;
                  }
                  await StorageService.addPlan(Plan(
                    id: const Uuid().v4(),
                    ticker: ticker.toUpperCase(),
                    name: name,
                    type: type,
                    targetQuantity: q,
                    targetPrice: p > 0 ? p : null,
                    targetDate: date,
                    note: payDate == null ? 'Подбор выплат' : 'Подбор выплат: купон ${Fmt.date(payDate)}',
                    createdAt: DateTime.now(),
                  ));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text('План «${_cap(name)}» добавлен')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
