import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/appearance_service.dart';
import 'tokens.dart';

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Нижняя навигация: ровная панель с тонкой линией сверху. Выбранная
/// вкладка — светлым, остальные серым; без подсветок и анимаций формы.
class AuroraNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  const AuroraNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 6, top: 8, left: 4, right: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _NavButton(
                  item: items[i],
                  selected: i == index,
                  onTap: () {
                    if (i != index) HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = context.isDark ? const Color(0xFFEEF1F6) : const Color(0xFF111318);
    final color = selected ? on : context.dim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.activeIcon : item.icon, size: 22, color: color),
          // Подписи можно убрать — останутся только значки.
          if (AppearanceService.showNavLabels) ...[
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: color),
            ),
          ],
        ],
      ),
    );
  }
}
