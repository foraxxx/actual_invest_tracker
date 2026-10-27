import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/appearance_service.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/backup_settings_service.dart';
import '../services/budget_service.dart';
import '../services/currency_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';
import '../services/portfolio_service.dart';
import '../services/sector_service.dart';
import '../services/tax_service.dart';
import '../services/theme_service.dart';
import '../services/home_widget_service.dart';
import 'annual_report_screen.dart';
import 'widget_constructor_screen.dart';
import 'broker_import_screen.dart';
import 'budget_screen.dart';
import 'home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Часть настроек относится к текущему портфелю — его название в подписях
    // должно обновляться, когда открыли другой портфель.
    PortfolioService.version.addListener(_onPortfolio);
  }

  @override
  void dispose() {
    PortfolioService.version.removeListener(_onPortfolio);
    super.dispose();
  }

  void _onPortfolio() {
    if (mounted) setState(() {});
  }

  String get _portfolioName => '«${PortfolioService.active.name}»';

  @override
  Widget build(BuildContext context) {
    return PageTour(
      pageId: 'settings',
      steps: const [
        PageTourStep(
          anchor: 'online',
          title: 'Биржа и котировки',
          text: 'Здесь включается загрузка с Мосбиржи: котировки, курсы валют, отрасли и '
              'логотипы бумаг. Без неё приложение работает полностью офлайн.',
        ),
        PageTourStep(
          anchor: 'portfolio',
          title: 'Портфель',
          text: 'Здесь создаются свои секторы — по ним строится диаграмма распределения. '
              'Привязать бумагу к сектору можно в её карточке. Тут же настраивается налог с продаж.',
        ),
        PageTourStep(
          anchor: 'data',
          title: 'Резервные копии',
          text: 'Данные лежат только на телефоне, поэтому бэкап — единственная страховка. '
              'Здесь же включается автосохранение в папку при каждом изменении.',
        ),
      ],
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          children: [
            Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            FadeSlideIn.staggered(
              index: 0,
              child: _navGroup([
                _navRow(
                  icon: Icons.save_outlined,
                  title: 'Данные',
                  value: _backupStatus(),
                  tourId: 'data',
                  open: () => _openGroup('Данные', () => [_dataSection()]),
                ),
              ]),
            ),
            FadeSlideIn.staggered(
              index: 1,
              child: _navGroup([
                _navRow(
                  icon: Icons.palette_outlined,
                  title: 'Оформление',
                  open: () => _openGroup('Оформление', () => [_appearanceSection()]),
                ),
                _navRow(
                  icon: Icons.widgets_outlined,
                  title: 'Виджет на экране',
                  value: _widgetSourceName(),
                  open: () => Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const WidgetConstructorScreen()),
                  ),
                ),
                _navRow(
                  icon: Icons.cloud_download_outlined,
                  title: 'Биржа и котировки',
                  value: OnlineSettingsService.enabled ? 'включено' : 'выключено',
                  tourId: 'online',
                  open: () => _openGroup(
                    'Биржа и котировки',
                    () => [_onlineSection(), const SizedBox(height: 14), _ratesSection()],
                  ),
                ),
              ]),
            ),
            FadeSlideIn.staggered(
              index: 2,
              child: _navGroup([
                _navRow(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Портфель',
                  value: PortfolioService.active.name,
                  tourId: 'portfolio',
                  open: () => _openGroup(
                    'Портфель',
                    () => [_sectorsSection(), const SizedBox(height: 14), _taxSection()],
                  ),
                ),
                _navRow(
                  icon: Icons.summarize_outlined,
                  title: 'Итоги года',
                  open: () => Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const AnnualReportScreen()),
                  ),
                ),
                _navRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Бюджет',
                  open: () => _openGroup('Бюджет', () => [_budgetSection()]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: context.dim),
                const SizedBox(width: 6),
                Text('Данные хранятся только на телефоне', style: TextStyle(color: context.dim, fontSize: 11.5)),
              ],
            ),
            const SizedBox(height: kListBottomPadding),
          ],
        ),
      ),
      ),
    );
  }

  /// Раздел настроек — строка в группе, открывает свою страницу.
  void _openGroup(String title, List<Widget> Function() builder) {
    Navigator.push(
      context,
      AppPageRoute(builder: (_) => _SettingsGroupScreen(title: title, children: builder)),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  String _backupStatus() {
    final at = BackupSettingsService.lastBackupAt;
    if (!BackupSettingsService.enabled || at == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'бэкап сегодня';
    if (diff == 1) return 'бэкап вчера';
    return 'бэкап ${at.day}.${at.month.toString().padLeft(2, '0')}';
  }

  String _widgetSourceName() {
    final id = HomeWidgetService.source;
    if (id == HomeWidgetService.allId) return 'все портфели';
    for (final p in PortfolioService.list) {
      if (p.id == id) return p.name;
    }
    return '';
  }

  Widget _navGroup(List<Widget> rows, {double indent = 52}) {
    final line = context.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: indent, color: line),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String title,
    required VoidCallback open,
    String value = '',
    String? tourId,
  }) {
    final row = InkWell(
      onTap: open,
      borderRadius: AppRadius.all(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: context.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
              ),
              child: Icon(icon, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.dim),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
          ],
        ),
      ),
    );
    return tourId == null ? row : TourSpot(id: tourId, child: row);
  }


  /// Оформление: сверху тема и цвет одной карточкой, ниже переключатели и
  /// строки с текущим значением. Пояснение — в окне выбора, а не под каждым
  /// пунктом.
  Widget _appearanceSection() {
    return FadeSlideIn(
      child: ValueListenableBuilder<int>(
        valueListenable: AppearanceService.version,
        builder: (context, _, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeService.themeMode,
                    builder: (context, mode, _) => SegmentedToggle<ThemeMode>(
                      values: const [ThemeMode.system, ThemeMode.dark, ThemeMode.light],
                      selected: mode,
                      labelOf: (m) => switch (m) {
                        ThemeMode.system => 'Система',
                        ThemeMode.light => 'Светлая',
                        ThemeMode.dark => 'Тёмная',
                      },
                      onChanged: ThemeService.setThemeMode,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Цвета — одним рядом, лишние прокручиваются.
                  ValueListenableBuilder<Color>(
                    valueListenable: ThemeService.accentColor,
                    builder: (context, current, _) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                      child: Row(
                      children: [
                        for (final p in kPalettes)
                          Tooltip(
                            message: p.name,
                            child: Pressable(
                              onTap: () => ThemeService.setAccentColor(p.color),
                              child: Container(
                                width: 26,
                                height: 26,
                                margin: const EdgeInsets.only(right: 9),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p.color,
                                  border: Border.all(
                                    color: p.color.value == current.value
                                        ? (context.isDark ? Colors.white : Colors.black87)
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _navGroup(indent: 14, [
              _switchLine('Скрывать суммы', AppearanceService.hideAmounts, AppearanceService.setHideAmounts),
              _switchLine('Подписи в нижней панели', AppearanceService.showNavLabels, (v) async {
                await AppearanceService.setShowNavLabels(v);
                if (mounted) setState(() {});
              }),
              _choiceLine<HoldingsGrouping>(
                title: 'Состав портфеля',
                hint: 'Бумаги на главной сгруппированы: акции, облигации, фонды.',
                values: HoldingsGrouping.values,
                selected: AppearanceService.holdingsGrouping,
                labelOf: (g) => g.title,
                onChanged: AppearanceService.setHoldingsGrouping,
              ),
              _choiceLine<ChartHints>(
                title: 'Значения на графике',
                hint: 'Где видна дата и сумма, когда палец на графике.',
                values: ChartHints.values,
                selected: AppearanceService.chartHints,
                labelOf: (h) => h.title,
                onChanged: AppearanceService.setChartHints,
              ),
              _choiceLine<SectionPreview>(
                title: 'Свёрнутые разделы',
                hint: 'Как выглядят свёрнутые разделы на главной.',
                values: SectionPreview.values,
                selected: AppearanceService.sectionPreview,
                labelOf: (p) => p.title,
                onChanged: AppearanceService.setSectionPreview,
              ),
              _choiceLine<PayoutCalendarStyle>(
                title: 'Календарь выплат',
                hint: '3 столбца — компактнее, 2 — с полными названиями месяцев.',
                values: PayoutCalendarStyle.values,
                selected: AppearanceService.payoutCalendar,
                labelOf: (c) => c.title,
                onChanged: AppearanceService.setPayoutCalendar,
              ),
              _choiceLine<MetricsLayout>(
                title: 'Показатели на главной',
                hint: 'Плитками или списком.',
                values: MetricsLayout.values,
                selected: AppearanceService.metricsLayout,
                labelOf: (c) => c.title,
                onChanged: AppearanceService.setMetricsLayout,
              ),
              _choiceLine<int>(
                title: 'Стартовая вкладка',
                hint: 'Что открывается при входе в портфель.',
                values: const [0, 1, 2, 3],
                selected: AppearanceService.startTab,
                labelOf: (i) => const ['Портфель', 'Биржа', 'Сделки', 'Планы'][i],
                onChanged: AppearanceService.setStartTab,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Строка с переключателем.
  Widget _switchLine(String title, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );

  /// Строка с текущим значением справа. Нажатие — окно выбора с коротким
  /// пояснением.
  Widget _choiceLine<T>({
    required String title,
    required String hint,
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required Future<void> Function(T) onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showAppSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(title: title, subtitle: hint),
                  const SizedBox(height: 6),
                  for (final v in values)
                    ListTile(
                      title: Text(labelOf(v)),
                      trailing: v == selected ? Icon(Icons.check_rounded, color: ctx.accent) : null,
                      onTap: () => Navigator.pop(ctx, v),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) await onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                labelOf(selected).toLowerCase(),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13.5, color: context.dim),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
          ],
        ),
      ),
    );
  }

  Widget _ratesSection() {
    return FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: _section(
                  title: 'Курсы валют',
                  subtitle: 'Загружаются с биржи автоматически',
                  icon: Icons.currency_exchange_rounded,
                  child: ValueListenableBuilder<int>(
                    valueListenable: CurrencyService.version,
                    builder: (context, _, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'С Мосбиржи. Сделка считается по курсу на её дату.',
                          style: TextStyle(fontSize: 11.5, height: 1.45, color: context.dim),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            for (final c in CurrencyService.trackedCurrencies) ...[
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      c,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: context.dim,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      CurrencyService.currentRate(c).toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${CurrencyService.historyFor(c).length} отм.',
                                      style: TextStyle(fontSize: 9.5, color: context.dim),
                                    ),
                                  ],
                                ),
                              ),
                              if (c != CurrencyService.trackedCurrencies.last)
                                Container(width: 1, height: 40, color: context.hairline),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
  }

  Widget _onlineSection() {
    return FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: _section(
                  title: 'Онлайн-данные',
                  subtitle: 'Котировки с Московской биржи',
                  icon: Icons.cloud_download_outlined,
                  child: const _OnlineDataSection(),
                ),
              );
  }

  Widget _sectorsSection() {
    return FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: _section(
                  title: 'Секторы',
                  subtitle: 'Используются в диаграмме распределения',
                  icon: Icons.pie_chart_outline_rounded,
                  child: const _SectorsSection(),
                ),
              );
  }

  Widget _taxSection() {
    return FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: _section(
                  title: 'Налог с продажи (НДФЛ)',
                  subtitle: 'Ставка и льгота на долгосрочное владение',
                  icon: Icons.receipt_long_rounded,
                  child: ValueListenableBuilder<int>(
                    valueListenable: TaxService.version,
                    builder: (context, _, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'С прибыли от продажи. Бумаги старше 3 лет — без налога (ЛДВ).',
                          style: TextStyle(fontSize: 11.5, height: 1.45, color: context.dim),
                        ),
                        const SizedBox(height: 12),
                        _switchRow(
                          title: 'Показывать налог с продаж',
                          subtitle: 'НДФЛ и ЛДВ в расчётах',
                          value: TaxService.enabled,
                          onChanged: TaxService.setEnabled,
                        ),
                        const SizedBox(height: 12),
                        AnimatedOpacity(
                          duration: AppDuration.normal,
                          opacity: TaxService.enabled ? 1 : 0.4,
                          child: IgnorePointer(
                            ignoring: !TaxService.enabled,
                            child: SegmentedToggle<double>(
                              values: const [0.13, 0.15],
                              selected: TaxService.rate,
                              labelOf: (r) => '${(r * 100).toStringAsFixed(0)}%',
                              onChanged: TaxService.setRate,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
  }

  Widget _budgetSection() {
    return FadeSlideIn(
      child: _section(
        title: 'Бюджет',
        subtitle: 'Общие настройки для всех месяцев',
        icon: Icons.account_balance_wallet_outlined,
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _actionRow(
                icon: Icons.event_outlined,
                title: 'Дни зарплаты и аванса',
                subtitle: 'Названия и дни выплат',
                onTap: () => showPayDaysSheet(context),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<int>(
                valueListenable: BudgetService.version,
                builder: (context, _, __) => _switchRow(
                  title: 'Выплата в выходной или праздник',
                  subtitle: 'Выплата в выходной придёт в рабочий день раньше.',
                  value: BudgetService.shiftToWorkday,
                  onChanged: BudgetService.setShiftToWorkday,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataSection() {
    return FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: _section(
                  title: 'Данные',
                  subtitle: 'Резервные копии и восстановление',
                  icon: Icons.save_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _actionRow(
                        icon: Icons.ios_share_rounded,
                        title: 'Сохранить бэкап',
                        subtitle: 'Все портфели и бюджет в одном файле',
                        onTap: () => BackupService.exportToJson(),
                      ),
                      const SizedBox(height: 8),
                      _actionRow(
                        icon: Icons.file_download_outlined,
                        title: 'Восстановить из бэкапа',
                        subtitle: 'Из сохранённого файла',
                        onTap: () => _importBackup(context),
                      ),
                      const SizedBox(height: 8),
                      _actionRow(
                        icon: Icons.account_balance_outlined,
                        title: 'Импорт от брокера',
                        subtitle: 'Сделки и выплаты из отчёта брокера',
                        onTap: () => Navigator.push(
                          context,
                          AppPageRoute(builder: (_) => const BrokerImportScreen()),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _BackupCryptoSection(),
                      const SizedBox(height: 18),
                      const _AutoBackupSection(),
                    ],
                  ),
                ),
              );
  }

  /// Названия страниц настроек: у раздела с таким же заголовком подпись не
  /// нужна — она повторяла бы заголовок страницы.
  static const _pageTitles = {'Оформление', 'Бюджет', 'Данные'};

  /// Раздел внутри страницы настроек: короткая подпись и карточка.
  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_pageTitles.contains(title))
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.dim),
            ),
          ),
        AppCard(padding: const EdgeInsets.all(14), child: child),
      ],
    );
  }

  Widget _choiceTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11.3, height: 1.35, color: context.dim)),
      ],
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11.3, height: 1.35, color: context.dim)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
          borderRadius: AppRadius.all(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: context.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
          ],
        ),
      ),
    );
  }

  /// Спрашивает пароль от зашифрованной копии. Вызывается, только если файл
  /// действительно зашифрован, а сохранённый пароль не подошёл.
  Future<String?> _askBackupPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Файл зашифрован'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Введите пароль, которым была закрыта эта копия. '
              'Без него прочитать файл невозможно — пароль нигде не хранится, '
              'кроме устройства, где делался бэкап.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            AppTextField(controller: ctrl, label: 'Пароль', autofocus: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
  }

  /// Бюджет в бэкапе старее текущего: заменить или оставить нынешний.
  Future<bool> _confirmBudgetReplace(BuildContext context, DateTime? backupAt, DateTime? currentAt) async {
    String when(DateTime? d) => d == null ? 'неизвестно когда' : Fmt.dateTime(d);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Бюджет в бэкапе старее'),
        content: Text(
          'Бюджет в файле сохранён ${when(backupAt)}, а в приложении он менялся ${when(currentAt)}. '
          'Если заменить, отметки и изменения после даты бэкапа пропадут. Портфели загрузятся в любом случае.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Оставить текущий')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Заменить')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _importBackup(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт бэкапа'),
        content: const Text(
          'Данные из файла будут добавлены к тем, что уже есть в приложении '
          '(существующие записи не удаляются и не перезаписываются). Продолжить?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выбрать файл')),
        ],
      ),
    );
    if (confirm != true) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.single.path == null) return;

    try {
      final result = await BackupService.importFromFilePath(
        picked.files.single.path!,
        askPassword: () => _askBackupPassword(context),
        confirmBudget: (backupAt, currentAt) => _confirmBudgetReplace(context, backupAt, currentAt),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.portfolios > 0
                ? 'Загружено портфелей: ${result.portfolios}, записей: ${result.count}'
                : 'Импортировано записей: ${result.count}',
          ),
        ),
      );
      setState(() {});

      if (result.missingLogos.isNotEmpty) {
        if (!context.mounted) return;
        final wantsManualPick = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Не нашлись иконки бумаг'),
            content: Text(
              'Рядом с файлом бэкапа не нашлось ${result.missingLogos.length} '
              '${Fmt.plural(result.missingLogos.length, "иконка", "иконки", "иконок")} '
              '(${result.missingLogos.keys.join(", ")}). Часто причина в том, что проводник Android '
              'открывает временную копию файла, а не саму папку. Выбрать папку с иконками вручную?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Пропустить')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выбрать папку')),
            ],
          ),
        );
        if (wantsManualPick == true) {
          final folder = await FilePicker.platform.getDirectoryPath();
          if (folder != null) {
            final fixed = await BackupService.retryMissingLogos(result.missingLogos, folder);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(fixed > 0 ? 'Подтянуто иконок: $fixed' : 'В этой папке иконки не нашлись')),
            );
            setState(() {});
          }
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось прочитать файл: $e')),
      );
    }
  }
}

/// Управление секторами: создание/удаление и привязка бумаг.
class _SectorsSection extends StatefulWidget {
  const _SectorsSection();

  @override
  State<_SectorsSection> createState() => _SectorsSectionState();
}

class _SectorsSectionState extends State<_SectorsSection> {
  final _newSectorCtrl = TextEditingController();

  @override
  void dispose() {
    _newSectorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SectorService.version,
      builder: (context, _, __) {
        final customSectors = SectorService.customSectors;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (customSectors.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customSectors
                    .map((s) => Chip(
                          label: Text(s),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () => _confirmDeleteSector(context, s),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(child: AppTextField(controller: _newSectorCtrl, label: 'Новый сектор')),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () async {
                    if (_newSectorCtrl.text.trim().isEmpty) return;
                    await SectorService.addSector(_newSectorCtrl.text);
                    _newSectorCtrl.clear();
                  },
                  child: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Бумага привязывается к сектору в её карточке.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteSector(BuildContext context, String sector) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сектор?'),
        content: Text('Бумаги, привязанные к «$sector», вернутся к сектору по умолчанию.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await SectorService.removeSector(sector);
    }
  }
}

/// Автосохранение бэкапа: включение и выбор папки.
class _AutoBackupSection extends StatefulWidget {
  const _AutoBackupSection();

  @override
  State<_AutoBackupSection> createState() => _AutoBackupSectionState();
}

class _AutoBackupSectionState extends State<_AutoBackupSection> {
  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await BackupSettingsService.setFolderPath(path);
    await AutoBackupService.runNowIfEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BackupSettingsService.version,
      builder: (context, _, __) {
        final path = BackupSettingsService.folderPath;
        final enabled = BackupSettingsService.enabled;
        final last = BackupSettingsService.lastBackupAt;
        final error = BackupSettingsService.lastError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Автосохранение бэкапа',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
            ),
            const SizedBox(height: 6),
            Text(
              'Сохраняет бэкап в папку при каждом изменении. Не срабатывает — выберите «Загрузки».',
              style: TextStyle(fontSize: 11.3, height: 1.45, color: context.dim),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
                borderRadius: AppRadius.all(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Автосохранение включено',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          path ?? 'Сначала выберите папку ниже',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled && path != null,
                    onChanged: (v) async {
                      if (v && path == null) {
                        await _pickFolder();
                        if (BackupSettingsService.folderPath == null) return;
                      }
                      await BackupSettingsService.setEnabled(v);
                      if (v) await AutoBackupService.runNowIfEnabled();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Pressable(
              onTap: _pickFolder,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
                  borderRadius: AppRadius.all(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 20, color: context.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            path == null ? 'Выбрать папку' : 'Изменить папку',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          if (last != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Последнее сохранение: ${Fmt.date(last)} '
                                '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 11, color: context.dim),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
                  ],
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              InfoBanner(
                icon: Icons.error_outline_rounded,
                color: AppColors.negative,
                text: 'Последнее сохранение не удалось: $error\nПопробуйте выбрать другую папку.',
              ),
            ],
          ],
        );
      },
    );
  }
}


/// Настройки автоматической загрузки рыночных данных с Мосбиржи.
class _OnlineDataSection extends StatelessWidget {
  const _OnlineDataSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: OnlineSettingsService.version,
      builder: (context, _, __) {
        final enabled = OnlineSettingsService.enabled;
        final last = OnlineSettingsService.lastSyncAt;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Котировки с Мосбиржи, с задержкой около 15 минут.',
              style: TextStyle(fontSize: 11.3, height: 1.45, color: context.dim),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
                borderRadius: AppRadius.all(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Загружать котировки с биржи',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          last == null
                              ? 'Пока ни разу не загружалось'
                              : 'Последняя загрузка: ${Fmt.date(last)} '
                                  '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')} '
                                  '· бумаг: ${OnlineSettingsService.lastCount}',
                          style: TextStyle(fontSize: 11, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: (v) async {
                      await OnlineSettingsService.setEnabled(v);
                      MoexSyncService.instance.applySettings();
                    },
                  ),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 14),
              Text(
                'Как часто обновлять',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
              ),
              const SizedBox(height: 8),
              SegmentedToggle<int>(
                values: const [10, 30, 60, 300],
                selected: OnlineSettingsService.intervalSeconds,
                labelOf: (v) => v < 60 ? '$v с' : '${v ~/ 60} мин',
                onChanged: (v) async {
                  await OnlineSettingsService.setIntervalSeconds(v);
                  MoexSyncService.instance.applySettings();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Только пока приложение открыто и идут торги. Короткий интервал тратит батарею.',
                style: TextStyle(fontSize: 11, height: 1.4, color: context.dim),
              ),
            ],
          ],
        );
      },
    );
  }
}


/// Страница одного раздела настроек.
class _SettingsGroupScreen extends StatelessWidget {
  final String title;
  final List<Widget> Function() children;

  const _SettingsGroupScreen({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: children(),
      ),
    );
  }
}


/// Пароль на резервные копии.
class _BackupCryptoSection extends StatefulWidget {
  const _BackupCryptoSection();

  @override
  State<_BackupCryptoSection> createState() => _BackupCryptoSectionState();
}

class _BackupCryptoSectionState extends State<_BackupCryptoSection> {
  Future<void> _setPassword() async {
    final passCtrl = TextEditingController();
    final repeatCtrl = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Пароль для бэкапа'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Файл копии будет зашифрован этим паролем. Если Вы его забудете, '
                'восстановить данные из такой копии не сможет никто, включая меня.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: context.dim),
              ),
              const SizedBox(height: 14),
              AppTextField(controller: passCtrl, label: 'Пароль', autofocus: true),
              const SizedBox(height: 10),
              AppTextField(controller: repeatCtrl, label: 'Ещё раз'),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                final pass = passCtrl.text.trim();
                if (pass.length < 4) {
                  setDialogState(() => error = 'Хотя бы четыре символа');
                  return;
                }
                if (pass != repeatCtrl.text.trim()) {
                  setDialogState(() => error = 'Пароли не совпадают');
                  return;
                }
                await BackupCryptoService.setPassword(pass);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _remove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать пароль?'),
        content: const Text(
          'Новые копии будут сохраняться в открытом виде. Старые зашифрованные '
          'файлы останутся зашифрованными — для них пароль придётся ввести вручную.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (confirm == true) await BackupCryptoService.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BackupCryptoService.version,
      builder: (context, _, __) {
        final hasPassword = BackupCryptoService.hasPassword;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Шифрование копий',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
            ),
            const SizedBox(height: 6),
            Text(
              'С паролем файл бэкапа не прочитать без него. Пароль хранится на телефоне.',
              style: TextStyle(fontSize: 11.3, height: 1.45, color: context.dim),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
                borderRadius: AppRadius.all(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(
                    hasPassword ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 20,
                    color: hasPassword ? AppColors.positive : context.dim,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPassword ? 'Копии шифруются' : 'Копии сохраняются открытыми',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPassword
                              ? 'И ручной экспорт, и автосохранение'
                              : 'Любой, кто откроет файл, увидит весь портфель',
                          style: TextStyle(fontSize: 11, color: context.dim),
                        ),
                      ],
                    ),
                  ),
                  if (hasPassword)
                    Switch(
                      value: BackupCryptoService.enabled,
                      onChanged: (v) => BackupCryptoService.setEnabled(v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _setPassword,
                    icon: const Icon(Icons.key_rounded, size: 17),
                    label: Text(hasPassword ? 'Сменить пароль' : 'Задать пароль'),
                  ),
                ),
                if (hasPassword) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _remove,
                      icon: const Icon(Icons.lock_open_rounded, size: 17),
                      label: const Text('Убрать'),
                    ),
                  ),
                ],
              ],
            ),
            if (hasPassword) ...[
              const SizedBox(height: 10),
              const InfoBanner(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                text: 'Пароль восстановить нельзя. Если Вы его забудете, зашифрованная копия '
                    'останется нечитаемой навсегда — запишите его где-нибудь отдельно.',
              ),
            ],
          ],
        );
      },
    );
  }
}
