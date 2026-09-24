import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../services/plan_apply_service.dart';

/// Выбор плана для покупки: все активные планы по бумаге карточками, у
/// каждой — прогресс и то, как он изменится после этой покупки.
///
/// Одна и та же для формы в карточке бумаги и для формы во вкладке
/// «Сделки»: раньше в них были свои галка и выпадающий список, и поведение
/// двух форм расходилось.
///
/// «Не учитывать» — отдельная карточка, а не галка: так выбор всегда один и
/// виден целиком, без второго шага «включить, а потом выбрать».
class PlanPicker extends StatelessWidget {
  /// Кандидаты, см. [PlanApplyService.candidatesFor].
  final List<Plan> plans;

  /// Выбранный план; null — не учитывать.
  final String? selectedId;

  /// Сколько бумаг в покупке — для предпросмотра прогресса.
  final double quantity;

  final ValueChanged<String?> onChanged;

  const PlanPicker({
    super.key,
    required this.plans,
    required this.selectedId,
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Засчитать в план',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dim),
        ),
        const SizedBox(height: 8),
        for (final plan in plans) ...[
          _PlanCard(
            plan: plan,
            selected: plan.id == selectedId,
            quantity: quantity,
            onTap: () => onChanged(plan.id),
          ),
          const SizedBox(height: 6),
        ],
        Pressable(
          onTap: () => onChanged(null),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(AppRadius.md),
              border: Border.all(
                color: selectedId == null ? context.accent : context.hairline,
                width: selectedId == null ? 1.6 : 1,
              ),
            ),
            child: Text(
              'Не учитывать в планах',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selectedId == null ? FontWeight.w800 : FontWeight.w600,
                color: selectedId == null ? context.accent : context.dim,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final double quantity;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.quantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = plan.targetQuantity;
    final done = plan.purchasedQuantity;
    final add = selected ? PlanApplyService.allocation(plan, quantity) : 0.0;
    final extra = selected ? quantity - add : 0.0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = plan.targetDate;
    final overdue = date != null && date.isBefore(today);
    final future = date != null && date.isAfter(DateTime(now.year, now.month + 1, 0));

    double part(double v) => target <= 0 ? 0 : (v / target).clamp(0.0, 1.0);

    final String? note;
    final Color noteColor;
    if (!selected || add <= 0) {
      note = null;
      noteColor = context.dim;
    } else if (extra > 0) {
      // Главное, ради чего поле «сколько засчитано» и появилось: лишнее не
      // перевыполняет план, а остаётся обычной покупкой.
      note = 'Засчитается ${Fmt.qty(add)} шт, ещё ${Fmt.qty(extra)} — без плана';
      noteColor = AppColors.warning;
    } else if (done + add >= target) {
      note = 'План выполнится';
      noteColor = AppColors.positive;
    } else if (future) {
      note = 'Раньше срока';
      noteColor = context.dim;
    } else {
      note = null;
      noteColor = context.dim;
    }

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.md),
          color: selected ? AppColors.positive.withOpacity(context.isDark ? 0.08 : 0.06) : null,
          border: Border.all(
            color: selected ? AppColors.positive : context.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: date == null ? 'Без срока' : 'К ${Fmt.date(date)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        if (overdue)
                          const TextSpan(
                            text: '  просрочен',
                            style: TextStyle(fontSize: 11, color: AppColors.negative, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  add > 0
                      ? '${Fmt.qty(done)} → ${Fmt.qty(done + add)} из ${Fmt.qty(target)}'
                      : '${Fmt.qty(done)} из ${Fmt.qty(target)}',
                  style: TextStyle(fontSize: 12, color: context.dim, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 7),
            // Две части полосы: уже купленное сплошным цветом и то, что
            // добавит эта покупка, — полупрозрачным поверх.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: context.hairline)),
                    // alignment слева и heightFactor обязательны: без первого
                    // полоса росла бы от центра, без второго пустой
                    // ColoredBox получил бы нулевую высоту и не был виден.
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: part(done + add),
                      heightFactor: 1,
                      child: ColoredBox(color: AppColors.positive.withOpacity(0.45)),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: part(done),
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.positive),
                    ),
                  ],
                ),
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(
                note,
                style: TextStyle(fontSize: 11, color: noteColor, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
