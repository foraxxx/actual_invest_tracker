import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../design/fields.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/page_tour.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../data/securities.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/backup_settings_service.dart';
import '../services/currency_service.dart';
import '../services/favorites_service.dart';
import '../services/moex_service.dart';
import '../services/logo_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';
import '../services/sector_service.dart';
import '../services/tax_service.dart';
import '../services/theme_service.dart';
import 'annual_report_screen.dart';
import 'broker_import_screen.dart';
import 'home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
            const SizedBox(height: 2),
            Text(
              'Оформление, биржа, портфель и данные',
              style: TextStyle(fontSize: 12, color: context.dim),
            ),
            const SizedBox(height: 18),
            _group(
              index: 0,
              icon: Icons.palette_outlined,
              title: 'Оформление',
              subtitle: 'Акцентный цвет и тема',
              builder: () => [_appearanceSection()],
            ),
            _group(
              index: 1,
              icon: Icons.cloud_download_outlined,
              title: 'Биржа и котировки',
              subtitle: 'Загрузка с Мосбиржи, курсы валют, логотипы',
              tourId: 'online',
              builder: () => [_onlineSection(), const SizedBox(height: 14), _ratesSection()],
            ),
            _group(
              index: 2,
              icon: Icons.pie_chart_outline_rounded,
              title: 'Портфель',
              subtitle: 'Секторы и налог с продаж',
              tourId: 'portfolio',
              builder: () => [_sectorsSection(), const SizedBox(height: 14), _taxSection()],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FadeSlideIn.staggered(
                index: 3,
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const AnnualReportScreen()),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [context.accent.withOpacity(0.26), context.accent.withOpacity(0.08)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(Icons.summarize_outlined, size: 19, color: context.accent),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Итоги года',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                              'Отчёт по бумагам за год, с выгрузкой в PDF',
                              style: TextStyle(fontSize: 11.5, color: context.dim),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
                    ],
                  ),
                ),
              ),
            ),
            _group(
              index: 4,
              icon: Icons.save_outlined,
              title: 'Данные',
              subtitle: 'Резервные копии и восстановление',
              tourId: 'data',
              builder: () => [_dataSection()],
            ),
            const SizedBox(height: 22),
            Center(
              child: Column(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18, color: context.dim),
                  const SizedBox(height: 8),
                  Text(
                    'Данные хранятся на этом устройстве. В интернет приложение ходит\nтолько за котировками, и только если ты это разрешил.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.dim, fontSize: 11.5, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kListBottomPadding),
          ],
        ),
      ),
      ),
    );
  }

  /// Раздел настроек — строка в списке, которая открывает свою страницу.
  /// Раньше всё лежало одной простынёй, и найти нужное было тяжело.
  Widget _group({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> Function() builder,
    String? tourId,
  }) {
    final card = AppCard(
          padding: const EdgeInsets.all(14),
          onTap: () => Navigator.push(
            context,
            AppPageRoute(builder: (_) => _SettingsGroupScreen(title: title, children: builder)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [context.accent.withOpacity(0.26), context.accent.withOpacity(0.08)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, size: 19, color: context.accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11.5, color: context.dim)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
            ],
          ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeSlideIn.staggered(
        index: index,
        child: tourId == null ? card : TourSpot(id: tourId, child: card),
      ),
    );
  }


  Widget _appearanceSection() {
    return FadeSlideIn(
                child: _section(
                  title: 'Оформление',
                  subtitle: 'Акцентный цвет и тема',
                  icon: Icons.palette_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ValueListenableBuilder<Color>(
                        valueListenable: ThemeService.accentColor,
                        builder: (context, current, _) => Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: kPalettes.map((p) {
                            final selected = p.color.value == current.value;
                            return Pressable(
                              onTap: () async {
                                await ThemeService.setAccentColor(p.color);
                              },
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: AppDuration.normal,
                                    curve: Curves.easeOutBack,
                                    width: selected ? 50 : 44,
                                    height: selected ? 50 : 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: AppGradient.accent(p.color),
                                      border: Border.all(
                                        color: selected
                                            ? (context.isDark ? Colors.white : Colors.black87)
                                            : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: p.color.withOpacity(selected ? 0.5 : 0.25),
                                          blurRadius: selected ? 18 : 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 58,
                                    child: Text(
                                      p.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                        color: selected ? null : context.dim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService.themeMode,
                        builder: (context, mode, _) => SegmentedToggle<ThemeMode>(
                          values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                          selected: mode,
                          labelOf: (m) => switch (m) {
                            ThemeMode.system => 'Авто',
                            ThemeMode.light => 'Светлая',
                            ThemeMode.dark => 'Тёмная',
                          },
                          iconOf: (m) => switch (m) {
                            ThemeMode.system => Icons.brightness_auto_rounded,
                            ThemeMode.light => Icons.light_mode_rounded,
                            ThemeMode.dark => Icons.dark_mode_rounded,
                          },
                          onChanged: ThemeService.setThemeMode,
                        ),
                      ),

              const SizedBox(height: 22),
              Text(
                'Отображение',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<int>(
                valueListenable: AppearanceService.version,
                builder: (context, _, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _switchRow(
                      title: 'Скрывать суммы',
                      subtitle: 'Стоимость портфелей и позиций закрывается точками. '
                          'Нажатие по сумме показывает её, повторное нажатие снова скрывает.',
                      value: AppearanceService.hideAmounts,
                      onChanged: AppearanceService.setHideAmounts,
                    ),
                  ],
                ),
              ),
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
                          'Курсы приходят с валютного рынка Мосбиржи вместе с котировками. '
                          'Каждая сделка пересчитывается по курсу на её дату, а если связи нет — '
                          'берётся последний полученный курс.',
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
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
                          'Ставка применяется к прибыли от продажи бумаг, купленных менее 3 лет назад. '
                          'Владение от 3 лет освобождается от налога (ЛДВ) — упрощённо, без лимита суммы.',
                          style: TextStyle(fontSize: 11.5, height: 1.45, color: context.dim),
                        ),
                        const SizedBox(height: 12),
                        _switchRow(
                          title: 'Показывать налог с продаж',
                          subtitle: 'Расчёт НДФЛ и ЛДВ на главной и в карточке бумаги',
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
                        title: 'Экспортировать бэкап',
                        subtitle: 'Сохранить все данные в JSON-файл',
                        onTap: () => BackupService.exportToJson(),
                      ),
                      const SizedBox(height: 8),
                      _actionRow(
                        icon: Icons.file_download_outlined,
                        title: 'Импортировать бэкап',
                        subtitle: 'Восстановить данные из ранее сохранённого файла',
                        onTap: () => _importBackup(context),
                      ),
                      const SizedBox(height: 8),
                      _actionRow(
                        icon: Icons.account_balance_outlined,
                        title: 'Импорт от брокера',
                        subtitle: 'Сделки, выплаты и пополнения из отчёта',
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

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final accent = context.accent;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    colors: [accent.withOpacity(0.26), accent.withOpacity(0.08)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11.5, color: context.dim)),

                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
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
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh,
          borderRadius: AppRadius.all(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.3, color: context.dim)),
                ],
              ),
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
              'Введи пароль, которым была закрыта эта копия. '
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
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортировано записей: ${result.count}')),
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
              'Привязать бумагу к сектору можно в её карточке — так не приходится '
              'искать нужный тикер в общем списке.',
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
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
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
            ),
            const SizedBox(height: 6),
            Text(
              'Приложение само сохраняет JSON-бэкап текущего портфеля в выбранную папку при каждом '
              'изменении данных. На некоторых версиях Android доступны для записи не все папки — '
              'если не срабатывает, попробуй «Загрузки».',
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
                          path ?? 'Сначала выбери папку ниже',
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
                text: 'Последнее сохранение не удалось: $error\nПопробуй выбрать другую папку.',
              ),
            ],
          ],
        );
      },
    );
  }
}


/// Загрузка котировок с Мосбиржи. Пока это только проверка связи: цены
/// показываются в самой секции и никуда не сохраняются — так можно убедиться,
/// что биржа отвечает и числа разбираются верно, до того как они начнут
/// влиять на расчёты портфеля.
class _OnlineDataSection extends StatefulWidget {
  const _OnlineDataSection();

  @override
  State<_OnlineDataSection> createState() => _OnlineDataSectionState();
}

class _OnlineDataSectionState extends State<_OnlineDataSection> {
  bool _loading = false;
  bool _logosLoading = false;
  String? _logosResult;
  String? _error;

  /// Разовая попытка подтянуть логотипы для бумаг портфеля: удобно, чтобы не
  /// ждать, пока они появятся сами при пролистывании списков.
  Future<void> _fetchLogos() async {
    setState(() {
      _logosLoading = true;
      _logosResult = null;
    });
    await LogoService.forgetFailedAttempts();
    final snapshot = MoexSyncService.marketSnapshot.value;
    // Логотипы нужны и для избранного: это бумаги, которые ты смотришь часто.
    final map = <String, String>{
      for (final t in {...AnalyticsService.allOwnedTickers(), ...FavoritesService.all})
        t: snapshot[t]?.isin ?? '',
    };
    final result = await LogoService.fetchForAll(
      map,
      names: {
        for (final t in map.keys)
          t: snapshot[t]?.shortName ?? SecuritiesDatabase.byTicker(t)?.name ?? t,
      },
    );
    if (!mounted) return;
    setState(() {
      _logosLoading = false;
      final failed = result.failed;
      _logosResult = [
        'Подтянуто логотипов: ${result.loaded} из ${map.length}',
        if (failed.isNotEmpty) 'Не нашлись: ${failed.join(", ")}',
        if (failed.isNotEmpty)
          'Для них проверены адреса источников — если пришлёшь этот список, '
              'подберу рабочий. Логотип всегда можно поставить вручную в карточке бумаги.',
        // Полный журнал по каждой ненайденной бумаге: по нему сразу видно,
        // какой источник живой, а какой пора выбрасывать.
        for (final ticker in failed)
          '\n$ticker:\n${(LogoService.lastFailures[ticker.toUpperCase()] ?? const []).join("\n")}',
      ].join('\n');
    });
  }
  Map<String, MoexQuote> _quotes = {};
  List<String> _missing = [];

  Future<void> _check() async {
    final tickers = AnalyticsService.allOwnedTickers().toSet();
    setState(() {
      _loading = true;
      _error = null;
      _missing = [];
    });
    try {
      final quotes = await MoexService.fetchQuotes(tickers: tickers);
      await OnlineSettingsService.markSynced(quotes.length);
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _missing = tickers.where((t) => !quotes.containsKey(t)).toList()..sort();
        _loading = false;
      });
    } catch (e) {
      await OnlineSettingsService.markError('$e');
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

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
              'Приложение обращается только к iss.moex.com и только когда ты это разрешишь. '
              'Биржа отдаёт данные с задержкой около 15 минут, а вне торгов — цену последнего '
              'торгового дня, поэтому время котировки всегда показывается рядом с ней.',
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
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
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
                'Автообновление идёт только когда приложение открыто и торги идут. '
                'После закрытия таймер спит до следующей сессии; ручное обновление доступно '
                'всегда. Биржа отдаёт данные с задержкой около 15 минут, поэтому короткий '
                'интервал почти не добавляет свежести, но расходует трафик и батарею.',
                style: TextStyle(fontSize: 11, height: 1.4, color: context.dim),
              ),
            ],
            if (enabled) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _logosLoading ? null : _fetchLogos,
                icon: _logosLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined, size: 18),
                label: Text(_logosLoading ? 'Ищу логотипы…' : 'Подтянуть логотипы бумаг'),
              ),
              if (_logosResult != null) ...[
                const SizedBox(height: 8),
                Text(_logosResult!, style: TextStyle(fontSize: 11.5, color: context.dim)),
              ],
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _check,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: Text(_loading ? 'Спрашиваю биржу…' : 'Проверить связь'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              InfoBanner(
                icon: Icons.cloud_off_rounded,
                color: AppColors.negative,
                text: 'Не получилось: $_error',
              ),
            ],
            if (_quotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Ответ биржи',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
              ),
              const SizedBox(height: 8),
              ...(_quotes.values.toList()..sort((a, b) => a.ticker.compareTo(b.ticker))).map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 108,
                        child: Text(
                          q.ticker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Fmt.price(q.price, currency: '₽'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            Text(
                              '${q.board} · ${q.sourceField}'
                              '${q.faceValue != null ? " · номинал ${Fmt.price(q.faceValue!)}" : ""}',
                              style: TextStyle(fontSize: 10.5, color: context.dim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_missing.isNotEmpty) ...[
              const SizedBox(height: 6),
              InfoBanner(
                icon: Icons.help_outline_rounded,
                color: AppColors.warning,
                text: 'Не нашлись на бирже: ${_missing.join(", ")}. '
                    'Скорее всего, бумага торгуется в другом режиме — пришли мне этот список, добавлю режим.',
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
                'Файл копии будет зашифрован этим паролем. Забудешь его — '
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
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
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.dim),
            ),
            const SizedBox(height: 6),
            Text(
              'Бэкап содержит весь портфель целиком, а лежит он в «Загрузках», в облаке '
              'или в переписке. С паролем файл превращается в шифротекст: без пароля из него '
              'ничего не прочитать. Пароль хранится на этом устройстве, чтобы автосохранение '
              'работало само.',
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
                text: 'Пароль восстановить нельзя. Если забудешь его, зашифрованная копия '
                    'останется нечитаемой навсегда — запиши его где-нибудь отдельно.',
              ),
            ],
          ],
        );
      },
    );
  }
}
