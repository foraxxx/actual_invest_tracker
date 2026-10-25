import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/appearance_service.dart';
import 'motion.dart';
import 'tokens.dart';

/// Базовая карточка приложения: мягкая подложка, волосяная рамка и —
/// при желании — цветное свечение под ней. Заменяет собой Card во всех
/// новых экранах, чтобы вид был одинаковым везде.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? glow;
  final Border? border;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.md,
    this.color,
    this.glow,
    this.border,
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    // Плоский стиль: без свечения и теней — спокойнее и чуть дешевле в
    // отрисовке. Форма и отступы те же, чтобы вёрстка не менялась.
    // Мягкая карточка без рамки и свечения: блоки отделяются фоном и
    // отступами. В светлой теме — тонкая тень, иначе белое на светлом сливается.
    final isDark = context.isDark;
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isDark ? AppColors.darkSurface : AppColors.lightSurface),
        borderRadius: AppRadius.all(radius),
        border: border,
        boxShadow: isDark
            ? const []
            : [BoxShadow(color: const Color(0xFF0B1220).withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, child: card);
  }
}

/// Карточка «матовое стекло»: размывает то, что под ней (свечение фона),
/// и добавляет полупрозрачную заливку со светящейся кромкой. Используется
/// на главном экране поверх AuroraBackground.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? glow;
  final double blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadius.lg,
    this.glow,
    this.blur = 22,
  });

  @override
  Widget build(BuildContext context) {
    // В минималистичном дизайне «стекло» — та же спокойная карточка.
    return AppCard(padding: padding, radius: radius, child: child);
  }
}

/// «Живой» фон: несколько медленно дрейфующих размытых пятен света. Цвет
/// главного пятна зависит от результата портфеля — рост подсвечивается
/// зелёным, просадка розовым, а нейтральный баланс остаётся акцентным.
/// Работает и в тёмной, и в светлой теме (в светлой — деликатнее).
class AuroraBackground extends StatefulWidget {
  final double profit;
  final Widget child;
  final Color? accent;

  const AuroraBackground({super.key, required this.profit, required this.child, this.accent});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> {

  @override
  Widget build(BuildContext context) {
    // Ровный фон без пятен света: спокойнее и не отвлекает от цифр.
    return ColoredBox(
      color: context.isDark ? AppColors.darkBg : AppColors.lightBg,
      child: widget.child,
    );
  }
}

/// Заголовок секции: крупная подпись слева, опциональное действие справа
/// и тонкая акцентная «засечка», связывающая заголовок с контентом ниже.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: context.dim)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Плитка с одним показателем: иконка в цветном круге, подпись и значение,
/// которое умеет плавно докручиваться при изменении данных.
class StatTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final double? value;
  final String Function(double)? formatter;
  final String? text;
  final String? hint;
  final Color? hintColor;
  final VoidCallback? onTap;
  final bool compact;

  /// Вторая величина в той же плитке: подпись, значение и цвет значения.
  ///
  /// Нужна, чтобы парные показатели («вложено» и «свободно», «прибыль» и
  /// «из них выплаты») жили в одной карточке вместо двух. Оба числа видны
  /// сразу — без жеста, который пришлось бы сначала обнаружить.
  final String? secondLabel;
  final String? secondText;
  final Color? secondColor;

  /// Ряд переключателей под значением: подписи и индекс выбранной.
  ///
  /// В отличие от точек под свайпом, подписи сами говорят, что именно
  /// переключается — для XIRR и TWR это важно, потому что это два способа
  /// посчитать одно и то же, а не две разные величины.
  final List<String>? segments;
  final int selectedSegment;
  final ValueChanged<int>? onSegmentChanged;

  const StatTile({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.value,
    this.formatter,
    this.text,
    this.hint,
    this.hintColor,
    this.onTap,
    this.compact = false,
    this.secondLabel,
    this.secondText,
    this.secondColor,
    this.segments,
    this.selectedSegment = 0,
    this.onSegmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.accent;
    final interactive = onTap != null;
    return AppCard(
      onTap: onTap,
      glow: interactive ? c : null,
      border: interactive
          ? Border.all(color: c.withOpacity(context.isDark ? 0.52 : 0.38), width: 1.25)
          : null,
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: c.withOpacity(0.14),
                ),
                child: Icon(icon, size: 16, color: c),
              ),
              const SizedBox(width: 9),
              Expanded(
                // Длинные подписи вроде «Доход за период» не влезают в
                // половину ширины экрана — вместо обрезки многоточием текст
                // медленно едет и возвращается.
                child: AdaptiveSingleLineText(
                  label,
                  style: TextStyle(fontSize: 11.5, color: context.dim, fontWeight: FontWeight.w600),
                ),
              ),
              // Признак «открывается» стоит в строке заголовка: высоту она
              // задаёт иконкой слева, поэтому значок здесь бесплатен по
              // месту, в отличие от прежней отдельной строки со стрелкой.
              if (interactive) ...[
                const SizedBox(width: 5),
                // 20 пикселей, а не 22: в половину ширины экрана каждый
                // пиксель отнимается у заголовка, а тот при нехватке места
                // не обрезается, а ужимается в кегле — и карточка с шевроном
                // начинает выглядеть мельче соседней без него.
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.withOpacity(context.isDark ? 0.18 : 0.12),
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 15, color: c),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          if (value != null && formatter != null)
            RollingNumber(
              value: value!,
              formatter: formatter!,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            )
          else
            AdaptiveSingleLineText(
              text ?? '—',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
          // Подсказка идёт сразу под числом мелким кеглем.
          //
          // Раньше она жила в нижней строке фиксированной высоты вместе со
          // стрелкой: строка съедала 33 пикселя в каждой карточке, текст в
          // ней не помещался и ехал бегущей строкой под стрелку.
          //
          // Строка рисуется и без подсказки — пустой: прежняя нижняя строка
          // фиксированной высоты выравнивала соседние карточки, и без замены
          // плитка с подсказкой стала бы выше плитки без неё в том же ряду.
          // Цена вопроса теперь 13 пикселей вместо 33.
          if (!compact) ...[
            const SizedBox(height: 3),
            AdaptiveSingleLineText(
              hint ?? ' ',
              style: TextStyle(fontSize: 9.5, color: hintColor ?? context.dim),
            ),
          ],
          if (secondLabel != null && secondText != null) ...[
            const SizedBox(height: 9),
            Divider(height: 1, color: context.hairline),
            const SizedBox(height: 7),
            // Подпись сверху, сумма под ней во всю ширину.
            //
            // В одну строку подпись и сумма делили место поровну и ужимали
            // друг друга: «из них выплаты 42 932 ₽» уже на этих числах
            // читалось мельче соседей, а на миллионах стало бы совсем мелким.
            // Здесь сумме конкурировать не с кем.
            AdaptiveSingleLineText(
              secondLabel!,
              style: TextStyle(fontSize: 9.5, color: context.dim),
            ),
            const SizedBox(height: 1),
            AdaptiveSingleLineText(
              secondText!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: secondColor ?? context.dim,
              ),
            ),
          ],
          if (segments != null && segments!.length > 1) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
              ),
              child: Row(
                children: [
                  for (int i = 0; i < segments!.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onSegmentChanged?.call(i),
                        child: AnimatedContainer(
                          duration: AppDuration.fast,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: i == selectedSegment ? c.withOpacity(0.22) : Colors.transparent,
                          ),
                          child: Text(
                            segments![i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: i == selectedSegment ? FontWeight.w700 : FontWeight.w600,
                              color: i == selectedSegment ? c : context.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Единый отчётливый маркер того, что карточку можно открыть.
class InteractiveArrow extends StatelessWidget {
  final Color color;

  const InteractiveArrow({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(context.isDark ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: color.withOpacity(context.isDark ? 0.58 : 0.42),
        ),
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 18,
        color: color,
      ),
    );
  }
}

/// Небольшая цветная плашка-«таблетка» — статус, тег, знак прибыли.
class TagChip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  final double fontSize;

  const TagChip({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.filled = false,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 9 : 7, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: filled ? color : color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Горизонтальный переключатель-«таблетки». Выбранный элемент заливается
/// акцентным градиентом и плавно раздувается — заметно живее, чем ChoiceChip.
class PillTabs<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  const PillTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.padding = EdgeInsets.zero,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      children.add(Padding(
        padding: EdgeInsets.only(right: i == values.length - 1 ? 0 : 8),
        child: _Pill(
          label: labelOf(v),
          icon: iconOf?.call(v),
          selected: v == selected,
          onTap: () {
            if (v == selected) return;
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ));
    }

    if (!scrollable) {
      return Padding(
        padding: padding,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (int i = 0; i < values.length; i++)
            _Pill(
              label: labelOf(values[i]),
              icon: iconOf?.call(values[i]),
              selected: values[i] == selected,
              onTap: () {
                if (values[i] == selected) return;
                onChanged(values[i]);
                HapticFeedback.selectionClick();
              },
            ),
        ]),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        physics: const BouncingScrollPhysics(),
        children: children,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    // Выбранная «пилюля» — светлая с тёмным текстом (в светлой теме наоборот).
    final on = context.isDark ? const Color(0xFFEEF1F6) : const Color(0xFF111318);
    final onText = context.isDark ? AppColors.darkBg : Colors.white;
    return Pressable(
      haptic: false,
      scale: 1,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: selected ? on : (context.isDark ? AppColors.darkSurface : Colors.white),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? onText : context.dim),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? onText : context.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Информационная полоса: подсказка, предупреждение или ошибка.
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const InfoBanner({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      glow: onTap != null ? color : null,
      padding: const EdgeInsets.all(13),
      color: color.withOpacity(context.isDark ? 0.11 : 0.08),
      border: Border.all(color: color.withOpacity(0.28)),
      radius: AppRadius.sm,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.3, height: 1.35, color: color, fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Пустое состояние с медленно «дышащей» иконкой — экран без данных всё
/// равно должен выглядеть законченным, а не сломанным.
class EmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Transform.scale(scale: 0.94 + 0.06 * _c.value, child: child),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.12),
                ),
                child: Icon(widget.icon, size: 38, color: accent),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.8, height: 1.45, color: context.dim),
              ),
            ],
            if (widget.action != null) ...[
              const SizedBox(height: 20),
              widget.action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Кнопка с акцентным градиентом — главное действие формы.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final List<Color>? colors;
  final bool expand;

  /// Второстепенное действие — тёмная кнопка рядом с основной.
  final bool secondary;

  /// Длинная надпись может переноситься на вторую строку, а не обрезаться.
  final int maxLines;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.colors,
    this.expand = true,
    this.maxLines = 1,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return GradientButton(
        label: label,
        icon: icon,
        onPressed: onPressed,
        expand: expand,
        maxLines: maxLines,
        colors: [context.isDark ? AppColors.darkSurfaceHigh : const Color(0xFF3A3F4B)],
      );
    }
    // Главная кнопка — сплошная светлая (или своего цвета, если передан).
    final bg = colors?.first ?? (context.isDark ? const Color(0xFFEEF1F6) : const Color(0xFF111318));
    final fg = colors != null ? Colors.white : (context.isDark ? AppColors.darkBg : Colors.white);
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.sm + 2),
          color: bg,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
    return Pressable(onTap: onPressed, scale: 0.98, child: button);
  }
}

/// Шапка модального окна: «ручка», заголовок, подзаголовок и крестик.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: context.isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!, style: TextStyle(fontSize: 12, color: context.dim, height: 1.35)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

/// Единая точка показа модальных форм — со скруглением, размытым барьером
/// и корректной высотой при открытой клавиатуре.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    // Высокое окно не заезжает под строку с часами, сетью и батареей.
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          border: Border(
            top: BorderSide(color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06)),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: builder(ctx),
      );
    },
  );
}

/// Сумма, которую можно спрятать от посторонних глаз.
///
/// Когда скрытие включено, вместо числа рисуется блок из точек той же ширины —
/// вёрстка не прыгает. Нажатие по любой такой сумме открывает сразу все:
/// прятать по одной бессмысленно, всё равно видно соседнюю строку.
class HiddenAmount extends StatelessWidget {
  final Widget child;

  /// Примерная ширина маски: считается от длины текста, чтобы точки занимали
  /// столько же места, сколько занимало бы число.
  final double width;
  final double height;

  const HiddenAmount({
    super.key,
    required this.child,
    this.width = 90,
    this.height = 16,
  });

  /// Удобный конструктор для денежных строк: ширина подбирается по тексту.
  factory HiddenAmount.forText(String text, {required Widget child, double? fontSize}) {
    final size = fontSize ?? 14;
    return HiddenAmount(
      width: text.length * size * 0.56,
      height: size * 1.05,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppearanceService.version,
      builder: (context, _, __) => ValueListenableBuilder<bool>(
        valueListenable: AppearanceService.revealed,
        builder: (context, revealed, __) {
          if (!AppearanceService.hideAmounts) return child;

          return GestureDetector(
            onTap: AppearanceService.toggleReveal,
            behavior: HitTestBehavior.opaque,
            child: revealed
                ? child
                : SizedBox(
                    width: width,
                    height: height,
                    child: CustomPaint(
                      painter: _MaskPainter(color: context.dim.withOpacity(0.55)),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final Color color;

  const _MaskPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * 0.17;
    final gap = radius * 3.1;
    final paint = Paint()..color = color;
    final y = size.height / 2;

    for (double x = radius; x < size.width - radius / 2; x += gap) {
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) => old.color != color;
}

/// Стрелка сворачиваемого блока — одна и та же во всём приложении.
class FoldArrow extends StatelessWidget {
  final bool open;
  const FoldArrow({super.key, required this.open});

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: AppDuration.fast,
        child: Icon(Icons.expand_more_rounded, size: 22, color: context.dim),
      );
}
