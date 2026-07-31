import 'package:flutter/material.dart';
import '../design/charts.dart';
import '../design/page_tour.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/portfolio_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';

/// Стартовый экран приложения: все портфели со сводкой сверху. Тап по
/// портфелю делает его активным и открывает — дальше весь интерфейс
/// работает уже с ним.
class PortfoliosScreen extends StatefulWidget {
  const PortfoliosScreen({super.key});

  @override
  State<PortfoliosScreen> createState() => _PortfoliosScreenState();
}

class _PortfolioStat {
  final double valueRub;
  final double profitRub;
  const _PortfolioStat({required this.valueRub, required this.profitRub});
}

class _PortfoliosScreenState extends State<PortfoliosScreen> {
  Map<String, _PortfolioStat> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PortfolioService.version.addListener(_onPortfoliosChanged);
    _load();
  }

  @override
  void dispose() {
    PortfolioService.version.removeListener(_onPortfoliosChanged);
    super.dispose();
  }

  void _onPortfoliosChanged() => _load();

  Future<void> _load() async {
    final stats = <String, _PortfolioStat>{};
    for (final p in PortfolioService.list) {
      final data = await StorageService.readDataFor(p.id);
      final summary = AnalyticsService.summaryFor(purchases: data.purchases, incomes: data.incomes);
      stats[p.id] = _PortfolioStat(valueRub: summary.valueRub, profitRub: summary.profitRub);
    }
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _openPortfolio(PortfolioMeta p) async {
    if (p.id != PortfolioService.activeId) {
      await PortfolioService.switchTo(p.id);
    }
    if (!mounted) return;
    await Navigator.push(context, AppPageRoute(builder: (_) => const HomeScreen()));
    // Пока пользователь был внутри портфеля, он мог что-то купить или продать —
    // по возвращении пересчитываем стоимость и прибыль заново.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = PortfolioService.list;
    final active = list.where((p) => p.status == PortfolioStatus.active).toList();
    final closed = list.where((p) => p.status == PortfolioStatus.closed).toList();

    final totalValue = active.fold(0.0, (s, p) => s + (_stats[p.id]?.valueRub ?? 0));
    final totalProfit = active.fold(0.0, (s, p) => s + (_stats[p.id]?.profitRub ?? 0));

    final distribution = <String, double>{};
    for (final p in active) {
      final v = _stats[p.id]?.valueRub ?? 0;
      if (v > 0) distribution[p.name] = v;
    }

    return PageTour(
      pageId: 'portfolios',
      steps: const [
        PageTourStep(
          anchor: 'summary',
          title: 'Сводка по всем портфелям',
          text: 'Общая стоимость активных портфелей и суммарная прибыль. Закрытые портфели '
              'сюда не входят — они остаются в истории.',
        ),
        PageTourStep(
          anchor: 'card',
          title: 'Портфель',
          text: 'Нажми, чтобы открыть: внутри своя история сделок, выплат и планов. '
              'Долгий список кнопок справа — переименовать, закрыть или удалить.',
        ),
        PageTourStep(
          anchor: 'fab',
          title: 'Новый портфель',
          text: 'Брокерский счёт и ИИС удобно вести раздельно: у каждого портфеля своя '
              'статистика и свои налоги.',
        ),
      ],
      child: Scaffold(
      body: AuroraBackground(
        profit: totalProfit,
        child: SafeArea(
          bottom: false,
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: 'Портфелей нет',
                  subtitle: 'Создай первый портфель — в нём будут храниться сделки, выплаты и планы.',
                  action: GradientButton(
                    label: 'Создать портфель',
                    icon: Icons.add_rounded,
                    expand: false,
                    onPressed: _createDialog,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'INVEST TRACKER',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                  color: context.dim,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text('Портфели', style: Theme.of(context).textTheme.headlineMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    FadeSlideIn(
                      child: TourSpot(
                        id: 'summary',
                        child: _summaryCard(totalValue, totalProfit, active.length),
                      ),
                    ),

                    if (distribution.length > 1) ...[
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                          child: Column(
                            children: [
                              const SectionTitle(
                                title: 'Распределение между портфелями',
                                padding: EdgeInsets.only(bottom: 12),
                              ),
                              DonutChart(
                                data: distribution,
                                valueFormatter: (v) => Fmt.money(v),
                                centerLabel: 'Всего',
                                size: 190,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (active.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionHeader('Активные', active.length),
                      for (int i = 0; i < active.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FadeSlideIn.staggered(
                            index: i,
                            child: i == 0
                                ? TourSpot(
                                    id: 'card',
                                    child: _portfolioCard(active[i], list.length, totalValue),
                                  )
                                : _portfolioCard(active[i], list.length, totalValue),
                          ),
                        ),
                    ],

                    if (closed.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _sectionHeader('Закрытые', closed.length),
                      for (final p in closed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _portfolioCard(p, list.length, totalValue),
                        ),
                    ],

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
        onPressed: _createDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Портфель', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      ),
    );
  }

  Widget _summaryCard(double value, double profit, int count) {
    final accent = context.accent;
    return GlassCard(
      glow: accent,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Активные портфели · $count',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dim),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Shimmer(width: 200, height: 38, radius: 10),
            )
          else
            HiddenAmount.forText(
              Fmt.money(value),
              fontSize: 34,
              child: RollingNumber(
                value: value,
                formatter: (v) => Fmt.money(v),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.4),
              ),
            ),
          const SizedBox(height: 10),
          if (_loading)
            const Shimmer(width: 140, height: 16, radius: 8)
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.pnl(profit).withOpacity(0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    profit >= 0 ? Icons.arrow_outward_rounded : Icons.south_east_rounded,
                    size: 14,
                    color: AppColors.pnl(profit),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Fmt.signedMoney(profit),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.pnl(profit),
                  ),
                ),
                const SizedBox(width: 6),
                Text('суммарной прибыли', style: TextStyle(fontSize: 11.5, color: context.dim)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.dim)),
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard(PortfolioMeta p, int totalCount, double totalValue) {
    final isActive = p.id == PortfolioService.activeId;
    final isClosed = p.status == PortfolioStatus.closed;
    final stat = _stats[p.id];
    final accent = context.accent;
    final share = (totalValue <= 0 || stat == null) ? 0.0 : stat.valueRub / totalValue;

    return AppCard(
      onTap: () => _openPortfolio(p),
      padding: const EdgeInsets.all(14),
      glow: isActive ? accent : null,
      border: Border.all(
        color: isActive ? accent.withOpacity(0.45) : context.hairline,
        width: isActive ? 1.4 : 1,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: isActive
                      ? AppGradient.accent(accent)
                      : LinearGradient(
                          colors: [accent.withOpacity(0.18), accent.withOpacity(0.06)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
                child: Icon(
                  isClosed ? Icons.lock_outline_rounded : Icons.account_balance_wallet_outlined,
                  size: 21,
                  color: isActive ? Colors.white : accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isActive) TagChip(text: 'текущий', color: accent, fontSize: 9.5),
                        TagChip(
                          text: isClosed ? 'закрыт' : 'активен',
                          color: isClosed ? AppColors.neutral : AppColors.positive,
                          fontSize: 9.5,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_loading)
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Shimmer(width: 78, height: 15, radius: 6),
                    SizedBox(height: 6),
                    Shimmer(width: 54, height: 12, radius: 6),
                  ],
                )
              else if (stat != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HiddenAmount.forText(
                      Fmt.money(stat.valueRub),
                      fontSize: 14.5,
                      child: Text(
                        Fmt.money(stat.valueRub),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                    ),
                    const SizedBox(height: 3),
                    TagChip(
                      text: Fmt.signedMoney(stat.profitRub),
                      color: AppColors.pnl(stat.profitRub),
                      fontSize: 10,
                    ),
                  ],
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 19, color: context.dim),
                onSelected: (v) {
                  if (v == 'rename') _renameDialog(p);
                  if (v == 'close') PortfolioService.setStatus(p.id, PortfolioStatus.closed);
                  if (v == 'reopen') PortfolioService.setStatus(p.id, PortfolioStatus.active);
                  if (v == 'delete') _confirmDelete(p, totalCount);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  if (isClosed)
                    const PopupMenuItem(value: 'reopen', child: Text('Открыть заново'))
                  else
                    const PopupMenuItem(value: 'close', child: Text('Закрыть портфель')),
                  if (totalCount > 1)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить', style: TextStyle(color: AppColors.negative)),
                    ),
                ],
              ),
            ],
          ),
          if (!_loading && !isClosed && share > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: MiniProgressBar(value: share, color: accent)),
                const SizedBox(width: 8),
                Text(
                  '${(share * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.dim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый портфель'),
        content: AppTextField(controller: ctrl, label: 'Название', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await PortfolioService.create(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDialog(PortfolioMeta p) async {
    final ctrl = TextEditingController(text: p.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать портфель'),
        content: AppTextField(controller: ctrl, label: 'Название', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await PortfolioService.rename(p.id, ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(PortfolioMeta p, int totalCount) async {
    if (totalCount <= 1) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить портфель?'),
        content: Text(
          'Все сделки, выплаты, планы и секторы портфеля «${p.name}» будут удалены '
          'без возможности восстановления.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PortfolioService.delete(p.id);
    }
  }
}
