import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../services/plan_apply_service.dart';

/// Выбор плана для покупки: одна строка с выбранным планом и тем, сколько
/// станет после сделки. Нажатие открывает список планов по бумаге и
/// «Не засчитывать».
///
/// Одна и та же для формы в карточке бумаги и для формы во вкладке
/// «Сделки»: раньше в них были свои галка и выпадающий список, и поведение
/// двух форм расходилось.
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
    Plan? selected;
    for (final p in plans) {
      if (p.id == selectedId) selected = p;
    }
    final String title;
    final String sub;
    Color subColor = context.dim;
    if (selected == null) {
      title = 'Не засчитывать';
      sub = plans.length == 1 ? 'Есть 1 план по этой бумаге' : 'Планов по этой бумаге: ${plans.length}';
    } else {
      final d = selected.targetDate;
      final when = d == null
          ? 'Без срока'
          : selected.isMonthPlan
              ? 'На ${Fmt.monthTitle('${d.year}-${d.month}').split(' ').first.toLowerCase()}'
              : 'До ${Fmt.dayShort(d)}';
      title = '$when · ${Fmt.qty(selected.purchasedQuantity)} из ${Fmt.qty(selected.targetQuantity)} шт';
      final add = PlanApplyService.allocation(selected, quantity);
      final after = selected.purchasedQuantity + add;
      final target = selected.targetQuantity;
      final pct = target <= 0 ? 0 : (after / target * 100).clamp(0, 100).round();
      final extra = quantity - add;
      if (extra > 0 && add > 0) {
        sub = 'засчитается ${Fmt.qty(add)} шт, ещё ${Fmt.qty(extra)} — без плана';
        subColor = AppColors.warning;
      } else {
        sub = after >= target ? 'после сделки план выполнится' : 'после сделки — ${Fmt.qty(after)} из ${Fmt.qty(target)} · $pct%';
        if (after >= target) subColor = AppColors.positive;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text('Засчитать в план', style: TextStyle(fontSize: 12, color: context.dim)),
        ),
        Material(
          color: context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
          borderRadius: AppRadius.all(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _choose(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Icon(
                    selected == null ? Icons.flag_outlined : Icons.flag_rounded,
                    size: 20,
                    color: selected == null ? context.dim : AppColors.positive,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
                      ],
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: context.dim),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Список планов по бумаге и «Не засчитывать» — в листе снизу.
  Future<void> _choose(BuildContext context) async {
    final picked = await showAppSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Засчитать в план'),
              const SizedBox(height: 10),
              for (final plan in plans) ...[
                _PlanCard(
                  plan: plan,
                  selected: plan.id == selectedId,
                  quantity: quantity,
                  onTap: () => Navigator.pop(ctx, plan.id),
                ),
                const SizedBox(height: 6),
              ],
              Pressable(
                onTap: () => Navigator.pop(ctx, ''),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.all(AppRadius.md),
                    border: Border.all(
                      color: selectedId == null ? context.accent : context.hairline,
                      width: selectedId == null ? 1.6 : 1,
                    ),
                  ),
                  child: Text(
                    'Не засчитывать',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selectedId == null ? context.accent : context.dim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    onChanged(picked.isEmpty ? null : picked);
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
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        if (overdue)
                          const TextSpan(
                            text: '  просрочен',
                            style: TextStyle(fontSize: 11, color: AppColors.negative, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    maxLines: 2,
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
