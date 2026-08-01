import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../design/charts.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/income.dart';
import '../services/analytics_service.dart';
import '../services/payout_forecast_service.dart';
import '../services/storage_service.dart';
import '../widgets/security_picker_field.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/payout_forecast_sheet.dart';
import 'home_screen.dart';
import 'ticker_detail_screen.dart';

class IncomesScreen extends StatefulWidget {
  const IncomesScreen({super.key});

  @override
  State<IncomesScreen> createState() => _IncomesScreenState();
}

class _IncomesScreenState extends State<IncomesScreen> {
  IncomeType? _filter;

  @override
  void initState() {
    super.initState();
    StorageService.dataVersion.addListener(_onDataChanged);
    // Прогноз приходит с биржи асинхронно: без подписки экран остаётся с
    // числом, посчитанным до загрузки графиков выплат.
    PayoutForecastService.version.addListener(_onDataChanged);
    PayoutForecastService.refresh();
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_onDataChanged);
    PayoutForecastService.version.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = StorageService.incomes..sort((a, b) => b.date.compareTo(a.date));
    final list = _filter == null ? all : all.where((i) => i.type == _filter).toList();

    final totalNet = AnalyticsService.totalIncome(f: PeriodFilter.all);
    final dividends = all.where((i) => i.type == IncomeType.dividend).length;
    final coupons = all.where((i) => i.type == IncomeType.coupon).length;
    final byMonth = AnalyticsService.incomeByMonth(f: PeriodFilter.year1);
    // Тот же расчёт, что и на главной: по объявленным биржей выплатам и
    // истории самой бумаги, а не по тому, что уже получено.
    final forecastSummary = PayoutForecastService.portfolioForecast();
    final forecast = forecastSummary.total;
    final forecastYield = PayoutForecastService.yieldPct();
    final taxTotal = all.fold<double>(0, (s, i) => s + i.taxPaid);

    return PageTour(
      pageId: 'payouts',
      steps: const [
        PageTourStep(
          anchor: 'fab',
          title: 'Новая выплата',
          text: 'Дивиденды и купоны, которые пришли на счёт. Сумма до налога и удержанный налог считаются отдельно.',
        ),
        PageTourStep(
          anchor: 'list',
          title: 'Полученные выплаты',
          text: 'Итог за период, прогноз на год и разбивка по месяцам.',
        ),
      ],
      child: Scaffold(
      body: TourSpot(
        id: 'list',
        child: SafeArea(
        bottom: false,
        child: all.isEmpty
            ? const EmptyState(
                icon: Icons.payments_rounded,
                title: 'Выплат пока нет',
                subtitle: 'Записывай сюда полученные дивиденды и купоны — приложение '
                    'посчитает доходность и построит прогноз на следующие 12 месяцев.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                children: [
                  Text('Выплаты', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Дивиденды и купоны · ${all.length} ${Fmt.payouts(all.length)}',
                    style: TextStyle(fontSize: 12, color: context.dim),
                  ),
                  const SizedBox(height: 16),

                  // --- Итог ---
                  FadeSlideIn(
                    child: GlassCard(
                      glow: AppColors.positive,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.positive.withOpacity(0.32),
                                      AppColors.positive.withOpacity(0.10),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.card_giftcard_rounded,
                                  size: 18,
                                  color: AppColors.positive,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  'Получено после налога',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.dim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          RollingNumber(
                            value: totalNet,
                            formatter: (v) => Fmt.money(v),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.4,
                              color: AppColors.positive,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _heroStat('Дивиденды', '$dividends'),
                              Container(width: 1, height: 30, color: context.hairline),
                              _heroStat('Купоны', '$coupons'),
                              if (taxTotal > 0) ...[
                                Container(width: 1, height: 30, color: context.hairline),
                                _heroStat('Удержан налог', Fmt.compact(taxTotal)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (forecast > 0) ...[
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: InfoBanner(
                        icon: Icons.auto_graph_rounded,
                        color: AppColors.violet,
                        onTap: () => showPayoutForecastSheet(context),
                        trailing: const InteractiveArrow(color: AppColors.violet),
                        text: 'Прогноз на 12 месяцев со следующего месяца: ~${Fmt.money(forecast)}'
                            '${forecastYield > 0 ? " (${forecastYield.toStringAsFixed(1)}% годовых)" : ""} — '
                            'по графику купонов и объявленным дивидендам на сегодняшнее '
                            'количество бумаг. Не гарантия.',
                      ),
                    ),
                  ],

                  if (byMonth.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 100),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionTitle(title: 'Выплаты по месяцам', subtitle: 'За последний год'),
                            BarsChart(
                              values: byMonth.values.toList(),
                              labels: byMonth.keys.map(Fmt.monthKeyLabel).toList(),
                              color: AppColors.positive,
                              valueFormatter: (v) => Fmt.money(v),
                              height: 170,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  PillTabs<IncomeType?>(
                    values: const [null, IncomeType.dividend, IncomeType.coupon],
                    selected: _filter,
                    labelOf: (t) => t == null
                        ? 'Все выплаты'
                        : (t == IncomeType.dividend ? 'Дивиденды' : 'Купоны'),
                    onChanged: (t) => setState(() => _filter = t),
                  ),
                  const SizedBox(height: 14),

                  ..._buildList(list),
                  const SizedBox(height: kListBottomPadding),
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
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Выплата', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      ),
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Builder(
        builder: (context) => Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.dim),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildList(List<Income> list) {
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('Нет выплат в этой категории', style: TextStyle(color: context.dim, fontSize: 13)),
          ),
        ),
      ];
    }

    final items = <Widget>[];
    String? lastMonth;
    for (int i = 0; i < list.length; i++) {
      final inc = list[i];
      final key = '${inc.date.year}-${inc.date.month.toString().padLeft(2, '0')}';
      if (key != lastMonth) {
        lastMonth = key;
        items.add(Padding(
          padding: EdgeInsets.only(top: items.isEmpty ? 0 : 16, bottom: 10, left: 4),
          child: Text(
            Fmt.monthTitle(key),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: context.dim),
          ),
        ));
      }
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FadeSlideIn.staggered(index: i, child: _incomeCard(inc)),
      ));
    }
    return items;
  }

  Widget _incomeCard(Income inc) {
    final isDiv = inc.type == IncomeType.dividend;
    return Dismissible(
      key: Key(inc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.md),
          gradient: LinearGradient(colors: [AppColors.negative.withOpacity(0.15), AppColors.negative]),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        StorageService.deleteIncome(inc.id);
        setState(() {});
      },
      child: AppCard(
        padding: const EdgeInsets.all(13),
        onTap: () => Navigator.push(
          context,
          AppPageRoute(builder: (_) => TickerDetailScreen(ticker: inc.ticker)),
        ),
        child: Row(
          children: [
            TickerAvatar(ticker: inc.ticker, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          inc.name.trim().isEmpty ? inc.ticker : inc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TagChip(
                        text: isDiv ? 'Дивиденд' : 'Купон',
                        color: isDiv ? AppColors.positive : AppColors.info,
                        fontSize: 9.5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inc.ticker,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.dim, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${Fmt.date(inc.date)}'
                    '${inc.taxPaid > 0 ? ' · налог ${Fmt.price(inc.taxPaid, currency: inc.currency)}' : ''}',
                    style: TextStyle(fontSize: 11.3, color: context.dim, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+${Fmt.price(inc.amountNet, currency: inc.currency == 'RUB' ? '₽' : inc.currency)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.positive),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Форма новой выплаты
  // ---------------------------------------------------------------------------

  void _showAddSheet(BuildContext context) {
    final tickerCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final taxCtrl = TextEditingController(text: '0');
    IncomeType type = IncomeType.dividend;
    String currency = 'RUB';
    DateTime date = DateTime.now();

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, keyboard + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: 'Новая выплата',
                  subtitle: 'Дивиденд или купон, уже полученный на счёт',
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(height: 18),
                SegmentedToggle<IncomeType>(
                  values: IncomeType.values,
                  selected: type,
                  labelOf: (t) => t == IncomeType.dividend ? 'Дивиденд' : 'Купон',
                  iconOf: (t) => t == IncomeType.dividend
                      ? Icons.trending_up_rounded
                      : Icons.receipt_long_rounded,
                  colorOf: (t) => t == IncomeType.dividend ? AppColors.positive : AppColors.info,
                  onChanged: (t) => setSheetState(() => type = t),
                ),
                const SizedBox(height: 14),
                SecurityPickerField(
                  onSelected: (s) {
                    tickerCtrl.text = s.ticker;
                    nameCtrl.text = s.name;
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(flex: 2, child: AppTextField(controller: nameCtrl, label: 'Название')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(controller: tickerCtrl, label: 'Тикер', upperCase: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(controller: amountCtrl, label: 'Сумма до налога', number: true),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(controller: taxCtrl, label: 'Налог удержан', number: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppDropdown<String>(
                        value: currency,
                        label: 'Валюта',
                        items: const ['RUB', 'USD', 'EUR', 'CNY']
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setSheetState(() => currency = v ?? 'RUB'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppDateField(
                        value: date,
                        label: 'Дата',
                        lastDate: DateTime.now(),
                        firstDate: DateTime(2010),
                        onPicked: (d) => setSheetState(() => date = d),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                GradientButton(
                  label: 'Добавить выплату',
                  icon: Icons.check_rounded,
                  colors: const [Color(0xFF0FA97E), Color(0xFF16D796)],
                  onPressed: () {
                    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                    final tax = double.tryParse(taxCtrl.text.replaceAll(',', '.')) ?? 0;
                    if (tickerCtrl.text.isEmpty || amount == null) return;
                    StorageService.addIncome(Income(
                      id: const Uuid().v4(),
                      date: date,
                      ticker: tickerCtrl.text.toUpperCase(),
                      name: nameCtrl.text.isEmpty ? tickerCtrl.text : nameCtrl.text,
                      type: type,
                      amountGross: amount,
                      taxPaid: tax,
                      currency: currency,
                    ));
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
