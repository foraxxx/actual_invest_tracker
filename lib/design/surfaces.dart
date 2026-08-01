import 'dart:math' as math;
import 'dart:ui';
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
    final flat = AppearanceService.cardStyle == CardStyle.flat;
    final isDark = context.isDark;
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isDark ? AppColors.darkSurface : AppColors.lightSurface),
        borderRadius: AppRadius.all(radius),
        border: border ?? Border.all(color: context.hairline, width: 1),
        boxShadow: flat ? const [] : [
          if (glow != null)
            BoxShadow(color: glow!.withOpacity(isDark ? 0.22 : 0.16), blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 8))
          else if (!isDark)
            BoxShadow(color: const Color(0xFF0B1220).withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6)),
        ],
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
    final flat = AppearanceService.cardStyle == CardStyle.flat;
    final isDark = context.isDark;
    final glowColor = glow ?? context.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.all(radius),
        boxShadow: flat ? const [] : [
          BoxShadow(
            color: glowColor.withOpacity(isDark ? 0.28 : 0.20),
            blurRadius: 36,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.all(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.03)]
                    : [Colors.white.withOpacity(0.92), Colors.white.withOpacity(0.72)],
              ),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.9),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
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

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final accent = widget.accent ?? context.accent;
    final mood = AppColors.pnl(widget.profit);
    final o = isDark ? 1.0 : 0.55;

    return Container(
      color: isDark ? AppColors.darkBg : AppColors.lightBg,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value * 2 * math.pi;
                  return Stack(
                    children: [
                      Positioned(
                        left: -60 + 70 * math.sin(t),
                        top: -110 + 45 * math.sin(t * 0.7),
                        child: _blob(accent.withOpacity(0.34 * o), 320),
                      ),
                      Positioned(
                        right: -80 + 60 * math.sin(t * 0.9 + 2),
                        top: 90 + 60 * math.sin(t * 0.5 + 1),
                        child: _blob(mood.withOpacity(0.22 * o), 260),
                      ),
                      Positioned(
                        left: 30 + 50 * math.sin(t * 0.6 + 4),
                        bottom: -120 + 40 * math.sin(t * 0.8),
                        child: _blob(AppColors.violet.withOpacity(0.16 * o), 300),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
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
          Container(
            width: 3,
            height: subtitle == null ? 16 : 30,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: AppGradient.accent(context.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
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
  final VoidCallback? onTap;
  final bool marqueeLabel;

  const StatTile({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.value,
    this.formatter,
    this.text,
    this.hint,
    this.onTap,
    this.marqueeLabel = false,
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
      padding: const EdgeInsets.all(14),
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
                  gradient: LinearGradient(
                    colors: [c.withOpacity(0.28), c.withOpacity(0.10)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, size: 16, color: c),
              ),
              const SizedBox(width: 9),
              Expanded(
                // Длинные подписи вроде «Доход за период» не влезают в
                // половину ширины экрана — вместо обрезки многоточием текст
                // медленно едет и возвращается.
                child: MarqueeText(
                  label,
                  alwaysScroll: marqueeLabel,
                  style: TextStyle(fontSize: 11.5, color: context.dim, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (value != null && formatter != null)
            RollingNumber(
              value: value!,
              formatter: formatter!,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            )
          else
            Text(
              text ?? '—',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (hint != null || interactive) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                if (hint != null)
                  Expanded(
                    child: MarqueeText(
                      hint!,
                      style: TextStyle(fontSize: 10.5, color: context.dim),
                    ),
                  )
                else
                  const Spacer(),
                if (interactive) ...[
                  if (hint != null) const SizedBox(width: 7),
                  InteractiveArrow(color: c),
                ],
              ],
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
    final accent = context.accent;
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
          gradient: selected ? AppGradient.accent(accent) : null,
          color: selected ? null : (context.isDark ? Colors.white.withOpacity(0.05) : Colors.white),
          border: Border.all(
            color: selected ? Colors.transparent : context.hairline,
          ),
          boxShadow: selected
              ? [BoxShadow(color: accent.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : context.dim),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : context.dim,
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
                  gradient: LinearGradient(
                    colors: [accent.withOpacity(0.22), accent.withOpacity(0.04)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: accent.withOpacity(0.22)),
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

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.colors,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors ?? AppGradient.pair(context.accent);
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.sm),
          gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: enabled
              ? [BoxShadow(color: c.first.withOpacity(0.38), blurRadius: 20, offset: const Offset(0, 8))]
              : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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
