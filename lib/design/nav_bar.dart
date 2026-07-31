import 'dart:ui';
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

/// Нижняя навигация: полупрозрачная панель с размытием, под выбранным
/// пунктом плавно переезжает акцентная «капля», иконка чуть подрастает,
/// а подпись проявляется только у активной вкладки — меньше визуального шума.
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
    final accent = context.accent;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8, top: 8, left: 8, right: 8),
          decoration: BoxDecoration(
            color: (isDark ? AppColors.darkBg : Colors.white).withOpacity(isDark ? 0.72 : 0.86),
            border: Border(top: BorderSide(color: context.hairline)),
          ),
          child: SizedBox(
            height: 56,
            child: LayoutBuilder(
              builder: (context, box) {
                final slot = box.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      left: slot * index + slot * 0.5 - 24,
                      top: 2,
                      width: 48,
                      height: 34,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: AppGradient.accent(accent),
                          boxShadow: [
                            BoxShadow(color: accent.withOpacity(0.42), blurRadius: 18, offset: const Offset(0, 6)),
                          ],
                        ),
                      ),
                    ),
                    Row(
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
                  ],
                );
              },
            ),
          ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: Center(
              child: AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: AppDuration.normal,
                curve: Curves.easeOutBack,
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 21,
                  color: selected ? Colors.white : context.dim,
                ),
              ),
            ),
          ),
          // Подписи можно убрать — останутся только значки.
          if (AppearanceService.showNavLabels) const SizedBox(height: 3),
          if (AppearanceService.showNavLabels)
            AnimatedDefaultTextStyle(
            duration: AppDuration.normal,
            style: TextStyle(
              fontSize: selected ? 10.5 : 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? context.accent : context.dim,
            ),
            child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
