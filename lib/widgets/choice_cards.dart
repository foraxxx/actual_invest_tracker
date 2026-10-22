import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';

/// Одна карточка-итог: «Выплаты ~58 673 ₽ за 12 месяцев».
class ChoiceCard {
  final String label;
  final String value;
  final String sub;
  final Color color;

  /// Сумма в рублях — прячется вместе с остальными суммами.
  final bool money;

  const ChoiceCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.money = false,
  });
}

/// Две карточки-итога рядом: видны оба числа, нажатие на карточку
/// переключает, что показано ниже. Используется в окнах «Прогноз» и
/// «Доходность».
class ChoiceCards extends StatelessWidget {
  final List<ChoiceCard> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const ChoiceCards({super.key, required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _card(context, items[i], i == selected, () => onSelect(i))),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ChoiceCard c, bool on, VoidCallback onTap) {
    final valueText = Text(
      c.value,
      maxLines: 1,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
        decoration: BoxDecoration(
          color: on ? c.color.withOpacity(0.13) : Colors.transparent,
          border: Border.all(color: on ? c.color : context.hairline, width: on ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: on ? 1 : 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? c.color : context.dim),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: c.money ? HiddenAmount.forText(c.value, fontSize: 17, child: valueText) : valueText,
              ),
              const SizedBox(height: 1),
              Text(
                c.sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, height: 1.25, color: context.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
