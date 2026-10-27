import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../services/manual_price_service.dart';
import '../services/plan_apply_service.dart';
import '../services/price_sanity_service.dart';
import '../services/storage_service.dart';
import '../services/tax_service.dart';
import '../services/moex_sync_service.dart';
import '../widgets/plan_picker.dart';
import '../widgets/security_picker_field.dart';
import '../widgets/selected_security_card.dart';
import '../widgets/undo_snack.dart';
import '../widgets/income_sheet.dart' show plainNumber;
import '../widgets/ticker_avatar.dart';
import '../widgets/trade_edit_sheet.dart';
import 'home_screen.dart';

/// Фильтр по типу операции.
enum _OpFilter { all, buy, sell }

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _searchCtrl = TextEditingController();
  _OpFilter _op = _OpFilter.all;
  AssetType? _type;
  int? _year = DateTime.now().year;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Экран живёт в IndexedStack и не пересоздаётся при переключении вкладок,
    // поэтому без слушателя смена портфеля не обновила бы список.
    StorageService.dataVersion.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_onDataChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  List<Purchase> get _filtered {
    var list = StorageService.purchases..sort((a, b) => b.date.compareTo(a.date));
    if (_year != null) list = list.where((p) => p.date.year == _year).toList();
    if (_op != _OpFilter.all) {
      final wantSell = _op == _OpFilter.sell;
      list = list.where((p) => p.isSell == wantSell).toList();
    }
    if (_type != null) list = list.where((p) => p.type == _type).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((p) => p.ticker.toLowerCase().contains(q) || p.name.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  List<int> get _availableYears {
    final years = <int>{
      DateTime.now().year,
      ...StorageService.purchases.map((purchase) => purchase.date.year),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  int get _activeFilterCount =>
      (_op == _OpFilter.all ? 0 : 1) +
      (_type == null ? 0 : 1) +
      (_year == DateTime.now().year ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final purchases = _filtered;
    final taxBreakdown = TaxService.enabled ? TaxService.saleTaxBreakdown() : <String, SaleTaxResult>{};

    final bought = purchases.where((p) => !p.isSell).fold(0.0, (s, p) => s + p.total);
    final sold =
        purchases.where((p) => p.isSell).fold(0.0, (s, p) => s + p.settlementAmount);

    return PageTour(
      pageId: 'purchases',
      steps: const [
        PageTourStep(
          anchor: 'fab',
          title: 'Новая сделка',
          text: 'Покупка или продажа. В одной форме можно записать сразу несколько бумаг одной датой.',
        ),
        PageTourStep(
          anchor: 'list',
          title: 'История сделок',
          text: 'Сгруппирована по месяцам. Поиск и фильтры сверху, свайп по карточке удаляет запись.',
        ),
      ],
      child: Scaffold(
      body: TourSpot(
        id: 'list',
        child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Сделки', style: Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 2),
                            Text(
                              '${purchases.length} ${Fmt.deals(purchases.length)} · '
                              '${_year ?? "все годы"}',
                              style: TextStyle(fontSize: 12, color: context.dim),
                            ),
                          ],
                        ),
                      ),
                      if (bought > 0 || sold > 0)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (bought > 0)
                              Text(
                                '− ${Fmt.money(bought)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            if (sold > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '+ ${Fmt.money(sold)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.negative,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: AppSearchField(
                          controller: _searchCtrl,
                          hint: 'Поиск по тикеру или названию',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _filterButton(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: purchases.isEmpty
                  ? EmptyState(
                      icon: Icons.swap_horiz_rounded,
                      title: StorageService.purchases.isEmpty ? 'Сделок ещё нет' : 'Ничего не найдено',
                      subtitle: StorageService.purchases.isEmpty
                          ? 'Нажмите «+ Сделка» внизу. Отчёт брокера можно загрузить в настройках.'
                          : 'Попробуйте изменить фильтры или поисковый запрос.',
                    )
                  : _buildList(purchases, taxBreakdown),
            ),
          ],
        ),
      ),
      ),
      floatingActionButton: TourSpot(
        id: 'fab',
        child: FloatingActionButton.extended(
        // Без heroTag Flutter считает все кнопки действия одной и той же и
        // при переходе между экранами перетекает одну в другую: на списке
        // портфелей «+ Портфель» на глазах превращался в «+ План».
        heroTag: null,
        onPressed: () => _showAddTradeSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Сделка', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      ),
      ),
    );
  }

  Widget _filterButton() {
    final active = _activeFilterCount;
    return Pressable(
      onTap: _openFilterSheet,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.sm),
          color: active > 0
              ? context.accent.withOpacity(0.16)
              : (context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
          border: Border.all(
            color: active > 0 ? context.accent.withOpacity(0.5) : context.hairline,
            width: active > 0 ? 1.4 : 1.2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 21,
              color: active > 0 ? context.accent : context.dim,
            ),
            if (active > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$active',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openFilterSheet() {
    var draftOp = _op;
    AssetType? draftType = _type;
    int? draftYear = _year;

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: 'Фильтры сделок',
                  subtitle: 'Год, операция и тип бумаги',
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Год',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final year in _availableYears)
                      _filterChoice(
                        label: '$year',
                        selected: draftYear == year,
                        onTap: () => setSheetState(() => draftYear = year),
                      ),
                    _filterChoice(
                      label: 'Все годы',
                      selected: draftYear == null,
                      onTap: () => setSheetState(() => draftYear = null),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Операция',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final op in _OpFilter.values)
                      _filterChoice(
                        label: switch (op) {
                          _OpFilter.all => 'Все операции',
                          _OpFilter.buy => 'Покупки',
                          _OpFilter.sell => 'Продажи',
                        },
                        selected: draftOp == op,
                        onTap: () => setSheetState(() => draftOp = op),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Тип бумаги',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChoice(
                      label: 'Все типы',
                      selected: draftType == null,
                      onTap: () => setSheetState(() => draftType = null),
                    ),
                    for (final type in AssetType.values)
                      _filterChoice(
                        label: Fmt.assetTypeShort(type),
                        selected: draftType == type,
                        onTap: () => setSheetState(() => draftType = type),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Применить',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    setState(() {
                      _op = draftOp;
                      _type = draftType;
                      _year = draftYear;
                    });
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => setSheetState(() {
                    draftOp = _OpFilter.all;
                    draftType = null;
                    draftYear = DateTime.now().year;
                  }),
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('Сбросить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? context.accent.withOpacity(0.16)
              : (context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? context.accent.withOpacity(0.55) : context.hairline,
            width: selected ? 1.4 : 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? context.accent : null,
          ),
        ),
      ),
    );
  }

  /// Список сделок с разделителями по месяцам — так проще искать глазами
  /// «что я делал в марте», чем в сплошной ленте.
  Widget _buildList(List<Purchase> purchases, Map<String, SaleTaxResult> tax) {
    // Сделки по месяцам: заголовок месяца и одна карточка, где сделки
    // разделены тонкой линией.
    final months = <String, List<Purchase>>{};
    for (final p in purchases) {
      final key = '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}';
      months.putIfAbsent(key, () => []).add(p);
    }
    final items = <Widget>[];
    var index = 0;
    var first = true;
    for (final e in months.entries) {
      // Последний месяц открыт, прошлые свёрнуты; выбор запоминается.
      final foldKey = 'deals:${e.key}';
      final saved = AppearanceService.ui(foldKey);
      final open = saved == null ? first : saved == 'open';
      first = false;
      final flow = e.value.fold(0.0, (s, p) => s + (p.isSell ? p.settlementAmount : -p.settlementAmount));
      final n = e.value.length;
      final title = Fmt.monthTitle(e.key);
      final year = '${DateTime.now().year}';
      final shortTitle = title.endsWith(' $year') ? title.substring(0, title.length - year.length - 1) : title;
      items.add(FadeSlideIn.staggered(
        index: index++,
        child: Padding(
          padding: EdgeInsets.only(top: items.isEmpty ? 0 : 10),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () async {
                    await AppearanceService.setUi(foldKey, open ? 'closed' : 'open');
                    if (mounted) setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(shortTitle, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        ),
                        HiddenAmount.forText(
                          '$n ${Fmt.deals(n)} · ${Fmt.money(flow)}',
                          fontSize: 12.5,
                          child: Text(
                            '$n ${Fmt.deals(n)} · ${flow > 0 ? '+' : ''}${Fmt.money(flow)}',
                            style: TextStyle(fontSize: 12.5, color: context.dim),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FoldArrow(open: open),
                      ],
                    ),
                  ),
                ),
                if (open)
                  for (int i = 0; i < e.value.length; i++) ...[
                    Divider(height: 1, thickness: 1, indent: i == 0 ? 0 : 64, color: context.hairline),
                    _tradeCard(e.value[i], tax[e.value[i].id]),
                  ],
              ],
            ),
          ),
        ),
      ));
    }
    items.add(const SizedBox(height: kListBottomPadding));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      children: items,
    );
  }

  Widget _tradeCard(Purchase p, SaleTaxResult? tax) {
    final color = p.isSell ? AppColors.negative : AppColors.positive;
    final taxLabel = tax == null ? null : _taxLabel(tax);
    return Dismissible(
      key: Key(p.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.negative,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) async {
        final copy = p.copy();
        await StorageService.deletePurchase(p.id);
        if (!mounted) return;
        setState(() {});
        showUndoSnack(context, 'Сделка удалена', () async {
          // Сохранение через правку пересчитывает и план, если сделка в нём.
          await StorageService.updatePurchase(copy);
          if (mounted) setState(() {});
        });
      },
      // Нажатие открывает правку сделки; из неё есть переход в карточку бумаги.
      child: InkWell(
        onTap: () async {
          await showEditTradeSheet(context, p, withTickerLink: true);
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  TickerAvatar(ticker: p.ticker, size: 38, glow: false),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: context.isDark ? AppColors.darkSurface : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        child: Icon(
                          p.isSell ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.ticker,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${p.isSell ? 'Продажа' : 'Покупка'} · ${Fmt.qty(p.quantity)} шт × '
                      '${Fmt.price(p.pricePerUnit, type: p.type)}'
                      '${p.fee > 0 ? ' · комиссия ${Fmt.qty(p.fee)}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: context.dim),
                    ),
                    if (taxLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(taxLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.warning)),
                      ),
                    if (p.note != null && p.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          p.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: context.dim),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${p.isSell ? '+' : '−'}${Fmt.group(p.settlementAmount)} ${p.currency == 'RUB' ? '₽' : p.currency}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.isSell ? AppColors.positive : null,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(Fmt.dayShort(p.date), style: TextStyle(fontSize: 12, color: context.dim)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _taxLabel(SaleTaxResult r) {
    if (r.realizedGainRub <= 0) return 'без налога (убыток)';
    if (r.taxableGainRub <= 0 && r.hasLdvPortion) return 'без налога (ЛДВ)';
    if (r.taxRub > 0) return 'налог ~${Fmt.money(r.taxRub)}';
    return null;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить сделку?'),
            content: const Text('Запись будет удалена без возможности восстановления.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.negative),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Если для позиции-покупки отмечена галка «Учитывать в ближайшем плане
  /// этого месяца» — находит ближайший (по дате) активный план ЭТОГО
  /// календарного месяца на этот тикер и записывает в него накопленное
  /// купленное количество и среднюю цену. При достижении цели план сразу
  /// отмечается выполненным.

  // ---------------------------------------------------------------------------
  // Форма новой сделки
  // ---------------------------------------------------------------------------

  void _showAddTradeSheet(BuildContext context) {
    DateTime date = DateTime.now();
    final positions = <_PositionDraft>[_PositionDraft()];

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final media = MediaQuery.of(ctx);
          final keyboard = media.viewInsets.bottom;
          final typing = keyboard > 0;
          // Когда клавиатура открыта, свободного места остаётся мало, поэтому
          // шапка ужимается до одной строки, а дата уезжает в прокручиваемую
          // часть: всё, кроме заголовка и кнопки сохранения, можно листать.
          final maxHeight = (media.size.height - keyboard - media.padding.top - 12)
              .clamp(260.0, media.size.height * 0.94);

          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, typing ? 8 : 14, 20, typing ? 4 : 12),
                    child: SheetHeader(
                      title: 'Новая сделка',
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      itemCount: positions.length + 1,
                      itemBuilder: (context, i) {
                        if (i == positions.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: TextButton.icon(
                              onPressed: () => setSheetState(() => positions.add(_PositionDraft())),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Ещё одна бумага'),
                            ),
                          );
                        }
                        return _PositionCard(
                          draft: positions[i],
                          index: i,
                          showIndex: positions.length > 1,
                          // Дата у сделки одна — поле в первой бумаге.
                          date: i == 0 ? date : null,
                          onDate: (d) => setSheetState(() => date = d),
                          onRemove: positions.length > 1
                              ? () => setSheetState(() => positions.removeAt(i))
                              : null,
                          onChanged: () => setSheetState(() {}),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.hairline)),
                    ),
                    child: GradientButton(
                      label: 'Сохранить · ${positions.length} ${Fmt.plural(positions.length, "позиция", "позиции", "позиций")}',
                      icon: Icons.check_rounded,
                      onPressed: () => _saveTrade(ctx, positions, date),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveTrade(BuildContext ctx, List<_PositionDraft> positions, DateTime date) async {
    // Проверяем, не пытаемся ли продать больше, чем есть в наличии.
    final sellTotals = <String, double>{};
    for (final pos in positions) {
      if (!pos.isSell) continue;
      final qty = pos.securityQuantity;
      if (pos.tickerCtrl.text.isEmpty || qty <= 0) continue;
      sellTotals[pos.tickerCtrl.text.toUpperCase()] =
          (sellTotals[pos.tickerCtrl.text.toUpperCase()] ?? 0) + qty;
    }
    final problems = <String>[];
    sellTotals.forEach((ticker, sellQty) {
      final available = AnalyticsService.currentHoldings()[ticker]?.qty ?? 0;
      if (sellQty > available + 1e-9) {
        problems.add('$ticker: в наличии ${Fmt.qty(available)} шт, Вы продаёте ${Fmt.qty(sellQty)} шт');
      }
    });
    if (problems.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: const Text('Продажа больше, чем есть'),
          content: Text(
            '${problems.join("\n")}\n\nЛишнее количество будет проигнорировано при расчётах. Всё равно продолжить?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Продолжить')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    int added = 0;
    for (final pos in positions) {
      final qty = pos.securityQuantity;
      final price = pos.unitPrice;
      if (pos.tickerCtrl.text.isEmpty || qty <= 0 || price <= 0) continue;
      final fee = double.tryParse(pos.feeCtrl.text.replaceAll(',', '.')) ?? 0;
      final ticker = pos.tickerCtrl.text.toUpperCase();
      final purchase = Purchase(
        id: const Uuid().v4(),
        date: date,
        ticker: ticker,
        name: pos.nameCtrl.text.isEmpty ? pos.tickerCtrl.text : pos.nameCtrl.text,
        type: pos.type,
        quantity: qty,
        pricePerUnit: price,
        fee: fee,
        currency: pos.currency,
        sector: pos.sector,
        isSell: pos.isSell,
        note: pos.noteCtrl.text.isEmpty ? null : pos.noteCtrl.text,
      );
      await StorageService.addPurchase(purchase);
      // Цена сделки фиксируется в истории цен только если она правдоподобна:
      // иначе опечатка переоценит всю позицию в графике портфеля, а не
      // только эту сделку.
      if (PriceSanityService.canRecordAsMarketPrice(ticker, price)) {
        await ManualPriceService.setAt(ticker, date, price);
      }
      if (!pos.isSell && pos.selectedPlanId != null) {
        Plan? plan;
        for (final p in PlanApplyService.candidatesFor(ticker)) {
          if (p.id == pos.selectedPlanId) plan = p;
        }
        if (plan != null) {
          // В план — только недостающее, остальное остаётся покупкой без
          // плана, а не перевыполняет его.
          final inPlan = PlanApplyService.allocation(plan, purchase.quantity);
          if (inPlan > 0) {
            await PlanApplyService.applyToPlan(purchase.id, plan.id, quantity: inPlan);
          }
        }
      }
      added++;
    }
    if (added > 0 && ctx.mounted) {
      Navigator.pop(ctx);
      if (mounted) setState(() {});
    }
  }
}

/// Черновик одной позиции внутри мультипозиционной сделки.
class _PositionDraft {
  final tickerCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final feeCtrl = TextEditingController(text: '0');
  final noteCtrl = TextEditingController();
  AssetType type = AssetType.stock;
  String currency = 'RUB';
  String? sector;
  bool isSell = false;
  /// В какой план засчитать позицию; null — не учитывать.
  ///
  /// В этой форме по умолчанию план не выбран: позиции тут часто вносят
  /// пачкой, и не каждая покупка относится к плану. Выбранная карточка при
  /// этом видна сразу, так что решение всё равно явное.
  String? selectedPlanId;
  int lotSize = 1;

  /// Бумаги нет в справочнике — название, тикер и тип вводятся вручную.
  bool manual = false;

  int get lots => int.tryParse(qtyCtrl.text.replaceAll(' ', '')) ?? 0;
  double get securityQuantity => lots * lotSize.toDouble();

  /// Цена за одну бумагу.
  double get unitPrice => double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;

  double get total {
    final p = unitPrice * securityQuantity;
    final f = double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 0;
    return isSell ? p - f : p + f;
  }
}

class _PositionCard extends StatelessWidget {
  final _PositionDraft draft;
  final int index;
  final bool showIndex;
  final DateTime? date;
  final ValueChanged<DateTime> onDate;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _PositionCard({
    required this.draft,
    required this.index,
    required this.showIndex,
    required this.date,
    required this.onDate,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = draft.isSell ? AppColors.negative : AppColors.positive;
    final chosen = draft.tickerCtrl.text.isNotEmpty && !draft.manual;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        color: context.isDark ? Colors.white.withOpacity(0.03) : AppColors.lightSurfaceHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (showIndex) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentColor),
                  ),
                ),
                const SizedBox(width: 10),
                ],
                Expanded(
                  child: SegmentedToggle<bool>(
                    values: const [false, true],
                    selected: draft.isSell,
                    labelOf: (v) => v ? 'Продажа' : 'Покупка',
                    onChanged: (v) {
                      draft.isSell = v;
                      onChanged();
                    },
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (chosen)
              SelectedSecurityCard(
                ticker: draft.tickerCtrl.text,
                name: draft.nameCtrl.text,
                type: draft.type,
                lotSize: draft.lotSize,
                isSell: draft.isSell,
                onChange: () {
                  draft.tickerCtrl.clear();
                  draft.nameCtrl.clear();
                  draft.selectedPlanId = null;
                  onChanged();
                },
              )
            else ...[
              SecurityPickerField(
                holdingsOnly: draft.isSell,
                onSelected: (s) {
                  draft.manual = false;
                  draft.tickerCtrl.text = s.ticker;
                  draft.nameCtrl.text = s.name;
                  draft.type = s.type;
                  draft.sector = s.sector;
                  final quote = MoexSyncService.marketSnapshot.value[s.ticker.toUpperCase()];
                  draft.lotSize = quote?.lotSize ?? 1;
                  if (draft.qtyCtrl.text.isEmpty) draft.qtyCtrl.text = '1';
                  // Текущая цена подставляется в поле — карточка её не пишет.
                  final currentPrice = quote?.price ?? AnalyticsService.priceFor(s.ticker);
                  if (currentPrice != null && currentPrice > 0) {
                    draft.priceCtrl.text = plainNumber(currentPrice);
                  }
                  draft.selectedPlanId = PlanApplyService.defaultFor(s.ticker)?.id;
                  onChanged();
                },
              ),
              if (!draft.manual)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      draft.manual = true;
                      onChanged();
                    },
                    child: const Text('Нет в списке — ввести вручную'),
                  ),
                )
              else ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: AppTextField(controller: draft.nameCtrl, label: 'Название'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                        controller: draft.tickerCtrl,
                        label: 'Тикер',
                        upperCase: true,
                        onChanged: (value) {
                          draft.lotSize = MoexSyncService
                                  .marketSnapshot.value[value.trim().toUpperCase()]?.lotSize ??
                              1;
                          onChanged();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppDropdown<AssetType>(
                  value: draft.type,
                  label: 'Тип актива',
                  icon: Icons.category_outlined,
                  items: AssetType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(Fmt.assetType(t))))
                      .toList(),
                  onChanged: (v) {
                    draft.type = v ?? AssetType.stock;
                    onChanged();
                  },
                ),
              ],
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: LotStepper(
                    controller: draft.qtyCtrl,
                    lotSize: draft.lotSize,
                    maxLots: draft.isSell ? _maxLots() : null,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: AppTextField(
                    controller: draft.priceCtrl,
                    label: 'Цена за бумагу',
                    number: true,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            LotCaption(
              lots: draft.lots,
              lotSize: draft.lotSize,
              maxLots: draft.isSell ? _maxLots() : null,
              onAll: () {
                draft.qtyCtrl.text = '${_maxLots()}';
                onChanged();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (date != null) ...[
                  Expanded(
                    flex: 3,
                    child: AppDateField(
                      value: date,
                      label: 'Дата',
                      lastDate: DateTime.now(),
                      firstDate: DateTime(2010),
                      onPicked: onDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    controller: draft.feeCtrl,
                    label: 'Комиссия',
                    number: true,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TradeSumLine(
              sum: draft.total,
              quantity: draft.securityQuantity,
              currency: draft.currency,
              isSell: draft.isSell,
            ),
            if (!draft.isSell && draft.tickerCtrl.text.isNotEmpty) _planSection(context),
          ],
        ),
      ),
    );
  }

  /// Сколько лотов можно продать — по тому, что есть на счету.
  int _maxLots() {
    final t = draft.tickerCtrl.text.toUpperCase();
    if (t.isEmpty) return 0;
    final qty = AnalyticsService.currentHoldings()[t]?.qty ?? 0;
    return (qty / (draft.lotSize <= 0 ? 1 : draft.lotSize)).floor();
  }

  /// Выбор плана для позиции — те же карточки, что в карточке бумаги.
  Widget _planSection(BuildContext context) {
    if (draft.isSell) return const SizedBox.shrink();
    final candidates = PlanApplyService.candidatesFor(draft.tickerCtrl.text);
    if (candidates.isEmpty) return const SizedBox.shrink();
    // Сменили бумагу — прежний выбор к её планам не относится.
    final selected = candidates.any((p) => p.id == draft.selectedPlanId) ? draft.selectedPlanId : null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PlanPicker(
        plans: candidates,
        selectedId: selected,
        quantity: draft.securityQuantity,
        onChanged: (id) {
          draft.selectedPlanId = id;
          onChanged();
        },
      ),
    );
  }
}
