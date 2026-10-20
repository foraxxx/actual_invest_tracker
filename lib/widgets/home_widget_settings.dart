import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/home_widget_service.dart';
import '../services/portfolio_service.dart';

/// Настройка виджета на экране телефона: какой портфель он показывает.
class HomeWidgetSettings extends StatefulWidget {
  const HomeWidgetSettings({super.key});

  @override
  State<HomeWidgetSettings> createState() => _HomeWidgetSettingsState();
}

class _HomeWidgetSettingsState extends State<HomeWidgetSettings> {
  late String _source = HomeWidgetService.source;

  Future<void> _pick(String id) async {
    setState(() => _source = id);
    await HomeWidgetService.setSource(id);
  }

  @override
  Widget build(BuildContext context) {
    final portfolios = PortfolioService.list;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Что показывает виджет', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Стоимость, изменение за сегодня и бюджет. Бюджет общий для всех портфелей.',
            style: TextStyle(fontSize: 11.5, height: 1.35, color: context.dim),
          ),
          const SizedBox(height: 14),
          _option(
            id: HomeWidgetService.allId,
            title: 'Все портфели вместе',
            subtitle: 'Стоимость и прибыль всех портфелей в сумме',
          ),
          for (final p in portfolios) ...[
            const SizedBox(height: 8),
            _option(id: p.id, title: p.name, subtitle: 'Только этот портфель'),
          ],
          const SizedBox(height: 16),
          Text(
            'Как добавить: долгое нажатие на пустом месте рабочего стола → «Виджеты» → '
            'Invest Tracker. Размер можно менять — раскладка подстраивается под 2×1, 4×1, 2×2 и 4×2.\n\n'
            'Виджет обновляет цены сам раз в полчаса, пока идут торги на бирже, и только '
            'при включённой загрузке котировок. Ночью и при низком заряде он не обновляется. '
            'Если включено «Скрывать суммы», на виджете вместо сумм точки, проценты видны.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: context.dim),
          ),
        ],
      ),
    );
  }

  Widget _option({required String id, required String title, required String subtitle}) {
    final selected = _source == id;
    final accent = context.accent;
    return Pressable(
      onTap: () => _pick(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? accent.withOpacity(0.12)
              : (context.isDark ? Colors.white.withOpacity(0.035) : AppColors.lightSurfaceHigh),
          borderRadius: AppRadius.all(AppRadius.sm),
          border: Border.all(color: selected ? accent.withOpacity(0.55) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? accent : context.dim,
            ),
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
          ],
        ),
      ),
    );
  }
}
