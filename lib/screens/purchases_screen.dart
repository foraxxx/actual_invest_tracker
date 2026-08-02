import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/manual_price_service.dart';
import '../services/plan_apply_service.dart';
import '../services/storage_service.dart';
import '../services/tax_service.dart';
import '../services/moex_sync_service.dart';
import '../widgets/security_picker_field.dart';
import '../widgets/ticker_avatar.dart';
import 'home_screen.dart';
import 'ticker_detail_screen.dart';

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
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                            if (sold > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '+ ${Fmt.money(sold)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
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
                          ? 'Нажмите «Сделка», чтобы записать покупку или продажу — можно сразу несколько бумаг за раз.'
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
                      fontWeight: FontWeight.w800,
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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
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
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? context.accent : null,
          ),
        ),
      ),
    );
  }

  /// Список сделок с разделителями по месяцам — так проще искать глазами
  /// «что я делал в марте», чем в сплошной ленте.
  Widget _buildList(List<Purchase> purchases, Map<String, SaleTaxResult> tax) {
    final items = <Widget>[];
    String? lastMonth;
    for (int i = 0; i < purchases.length; i++) {
      final p = purchases[i];
      final key = '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}';
      if (key != lastMonth) {
        lastMonth = key;
        items.add(Padding(
          padding: EdgeInsets.only(top: items.isEmpty ? 0 : 18, bottom: 10, left: 4),
          child: Text(
            Fmt.monthTitle(key),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: context.dim),
          ),
        ));
      }
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeSlideIn.staggered(index: i, child: _tradeCard(p, tax[p.id])),
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
    return Dismissible(
      key: Key(p.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      background: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.md),
          gradient: LinearGradient(
            colors: [AppColors.negative.withOpacity(0.15), AppColors.negative],
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        StorageService.deletePurchase(p.id);
        setState(() {});
      },
      child: AppCard(
        padding: const EdgeInsets.all(13),
        onTap: () => Navigator.push(
          context,
          AppPageRoute(builder: (_) => TickerDetailScreen(ticker: p.ticker)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                TickerAvatar(ticker: p.ticker, size: 42),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: context.isDark ? AppColors.darkSurface : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Icon(
                        p.isSell ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name.trim().isEmpty ? p.ticker : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TagChip(
                        text: p.isSell ? 'Продажа' : 'Покупка',
                        color: color,
                        fontSize: 9.5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.ticker,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.dim, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Fmt.date(p.date)} · ${Fmt.qty(p.quantity)} шт × ${Fmt.price(p.pricePerUnit, type: p.type)}'
                    '${p.fee > 0 ? ' · комиссия ${Fmt.qty(p.fee)}' : ''}',
                    style: TextStyle(fontSize: 11.3, color: context.dim, fontWeight: FontWeight.w600),
                  ),
                  if (p.sector != null && p.sector!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${Fmt.assetType(p.type)} · ${p.sector}',
                        style: TextStyle(fontSize: 11, color: context.dim),
                      ),
                    ),
                  if (tax != null && _taxLabel(tax) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TagChip(text: _taxLabel(tax)!, color: AppColors.warning, fontSize: 9.5),
                    ),
                  if (p.note != null && p.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        p.note!,
                        style: TextStyle(fontSize: 11.3, fontStyle: FontStyle.italic, color: context.dim),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${p.isSell ? '+' : '−'}${Fmt.group(p.settlementAmount)} ${p.currency == 'RUB' ? '₽' : p.currency}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: p.isSell ? AppColors.negative : null,
              ),
            ),
          ],
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
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
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
                      subtitle: typing ? null : 'Можно записать сразу несколько бумаг одной датой',
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      itemCount: positions.length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppDateField(
                              value: date,
                              label: 'Дата сделки',
                              lastDate: DateTime.now(),
                              firstDate: DateTime(2010),
                              onPicked: (d) => setSheetState(() => date = d),
                            ),
                          );
                        }
                        if (i == positions.length + 1) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => setSheetState(() => positions.add(_PositionDraft())),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Ещё одна бумага'),
                            ),
                          );
                        }
                        return _PositionCard(
                          draft: positions[i - 1],
                          index: i - 1,
                          onRemove: positions.length > 1
                              ? () => setSheetState(() => positions.removeAt(i - 1))
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
      final totalPrice = double.tryParse(pos.priceCtrl.text.replaceAll(',', '.'));
      if (pos.tickerCtrl.text.isEmpty || qty <= 0 || totalPrice == null || totalPrice <= 0) continue;
      final price = totalPrice / qty;
      final fee = double.tryParse(pos.feeCtrl.text.replaceAll(',', '.')) ?? 0;
      final ticker = pos.tickerCtrl.text.toUpperCase();
      await StorageService.addPurchase(Purchase(
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
      ));
      // Цена сделки — реальное наблюдение цены на эту дату, поэтому сразу
      // фиксируем её и в истории ручных цен.
      await ManualPriceService.setAt(ticker, date, price);
      if (!pos.isSell && pos.applyToNearestPlan) {
        await PlanApplyService.applyToNearestPlanThisMonth(ticker, qty, price);
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
  bool applyToNearestPlan = false;
  int lotSize = 1;

  int get lots => int.tryParse(qtyCtrl.text) ?? 0;
  double get securityQuantity => lots * lotSize.toDouble();

  void changeLots(int delta) {
    final oldQuantity = securityQuantity;
    final oldTotal = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
    final next = (lots + delta).clamp(1, 1000000);
    qtyCtrl.text = '$next';
    if (oldTotal != null && oldQuantity > 0) {
      priceCtrl.text = (oldTotal / oldQuantity * securityQuantity).toStringAsFixed(2);
    }
  }

  double get total {
    final p = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
    final f = double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 0;
    return isSell ? p - f : p + f;
  }
}

class _PositionCard extends StatelessWidget {
  final _PositionDraft draft;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _PositionCard({
    required this.draft,
    required this.index,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = draft.isSell ? AppColors.negative : AppColors.positive;
    final holding = draft.tickerCtrl.text.isEmpty
        ? null
        : AnalyticsService.currentHoldings()[draft.tickerCtrl.text.toUpperCase()];
    final hasHolding = holding != null && holding.qty > 0;

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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accentColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    draft.tickerCtrl.text.isEmpty
                        ? 'Бумага'
                        : draft.nameCtrl.text.trim().isEmpty
                            ? draft.tickerCtrl.text.toUpperCase()
                            : '${draft.nameCtrl.text.trim()} · ${draft.tickerCtrl.text.toUpperCase()}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                if (draft.total > 0)
                  Text(
                    Fmt.money(draft.total),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
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
            SegmentedToggle<bool>(
              values: const [false, true],
              selected: draft.isSell,
              labelOf: (v) => v ? 'Продажа' : 'Покупка',
              iconOf: (v) => v ? Icons.sell_outlined : Icons.add_shopping_cart_rounded,
              colorOf: (v) => v ? AppColors.negative : AppColors.positive,
              onChanged: (v) {
                draft.isSell = v;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            SecurityPickerField(
              onSelected: (s) {
                draft.tickerCtrl.text = s.ticker;
                draft.nameCtrl.text = s.name;
                draft.type = s.type;
                draft.sector = s.sector;
                final quote = MoexSyncService.marketSnapshot.value[s.ticker.toUpperCase()];
                draft.lotSize = quote?.lotSize ?? 1;
                if (draft.qtyCtrl.text.isEmpty) draft.qtyCtrl.text = '1';
                final currentPrice = quote?.price ?? AnalyticsService.priceFor(s.ticker);
                if (currentPrice != null && currentPrice > 0) {
                  draft.priceCtrl.text = (currentPrice * draft.securityQuantity).toStringAsFixed(2);
                }
                onChanged();
              },
            ),
            if (draft.isSell && draft.tickerCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 10),
              InfoBanner(
                icon: hasHolding ? Icons.inventory_2_outlined : Icons.error_outline_rounded,
                color: hasHolding ? AppColors.info : AppColors.negative,
                text: holding != null && holding.qty > 0
                    ? 'На счету: ${Fmt.qty(holding.qty)} шт по средней ${Fmt.price(holding.avgCost, type: draft.type)}'
                    : 'Этой бумаги нет на счету',
              ),
            ],
            const SizedBox(height: 12),
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
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Уменьшить на один лот',
                  onPressed: () {
                    draft.changeLots(-1);
                    onChanged();
                  },
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextField(
                    controller: draft.qtyCtrl,
                    label: 'Количество лотов',
                    number: true,
                    integerOnly: true,
                    suffixText: '× ${draft.lotSize} шт.',
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Добавить один лот',
                  onPressed: () {
                    draft.changeLots(1);
                    onChanged();
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InfoBanner(
              icon: Icons.inventory_2_outlined,
              color: AppColors.info,
              text: '${draft.lots} лот. × ${draft.lotSize} шт. = ${Fmt.qty(draft.securityQuantity)} шт.',
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: draft.priceCtrl,
              label: 'Стоимость всех выбранных бумаг',
              number: true,
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: draft.feeCtrl,
                    label: 'Комиссия',
                    number: true,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDropdown<String>(
                    value: draft.currency,
                    label: 'Валюта',
                    items: const ['RUB', 'USD', 'EUR', 'CNY']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      draft.currency = v ?? 'RUB';
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppTextField(controller: draft.noteCtrl, label: 'Заметка (необязательно)'),
            if (!draft.isSell) ...[
              const SizedBox(height: 4),
              AppCheckRow(
                value: draft.applyToNearestPlan,
                title: 'Учитывать в ближайшем плане этого месяца',
                subtitle: 'Запишет количество и среднюю цену в ближайший активный план '
                    'этого тикера с датой в текущем месяце; при достижении цели план станет выполненным',
                onChanged: (v) {
                  draft.applyToNearestPlan = v;
                  onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
