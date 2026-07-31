import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

/// Появление блока «снизу вверх с проявлением». Через [delay] элементы одного
/// списка выстраиваются в каскад: каждый следующий стартует чуть позже
/// предыдущего, и экран собирается на глазах, а не появляется рывком.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final double offsetX;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offsetY = 18,
    this.offsetX = 0,
  });

  /// Удобный конструктор для списков: индекс сам превращается в задержку,
  /// но не растёт бесконечно — иначе двадцатый элемент ждал бы секунду.
  factory FadeSlideIn.staggered({
    Key? key,
    required int index,
    required Widget child,
    double offsetY = 18,
    int stepMs = 45,
    int maxSteps = 8,
  }) {
    final step = index > maxSteps ? maxSteps : index;
    return FadeSlideIn(
      key: key,
      delay: Duration(milliseconds: step * stepMs),
      offsetY: offsetY,
      child: child,
    );
  }

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  // Задержка зашита В САМУ анимацию через Interval, а не в отдельный
  // Future.delayed: контроллер стартует сразу и всегда доходит до конца.
  // Раньше при не сработавшем таймере виджет навсегда оставался с
  // opacity 0 — занимал место в списке, но был невидим.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  )..forward();

  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: AppCurves.enter,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final t = _a.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(widget.offsetX * (1 - t), widget.offsetY * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Карточка/кнопка, которая «проминается» под пальцем. Отклик на нажатие —
/// главное, что отличает живой интерфейс от статичного макета.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down && enabled ? widget.scale : 1.0,
        duration: AppDuration.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Переход на новый экран с тем же характером, что и в теме, но доступный
/// точечно — например, когда нужно открыть деталь бумаги «изнутри» списка.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (context, a, b) => builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(parent: animation, curve: AppCurves.enter);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Плавно «прокручивающееся» число: при изменении значения счётчик
/// докручивается от старого к новому, а не перескакивает.
class RollingNumber extends StatelessWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  const RollingNumber({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 850),
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // begin намеренно не задан: TweenAnimationBuilder сам подставит туда
      // предыдущее отображённое значение и «докрутит» от него к новому.
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(
        formatter(animated),
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Мерцающий блик по плейсхолдеру — показываем, пока считается статистика
/// по всем портфелям, вместо голого спиннера.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Shimmer({super.key, required this.width, required this.height, this.radius = 8});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final glow = context.isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.10);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value - 0.6, 0),
              end: Alignment(-1 + 2 * _c.value + 0.6, 0),
              colors: [base, glow, base],
            ),
          ),
        );
      },
    );
  }
}

/// Текст, который не помещается в отведённую ширину, медленно едет по
/// горизонтали и возвращается — вместо многоточия. Если текст помещается,
/// виджет ведёт себя как обычный `Text` и ничего не анимирует.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  final bool alwaysScroll;

  /// Расстояние между концом текста и началом его повтора.
  final double gap;

  /// Скорость в логических пикселях в секунду.
  final double speed;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.align,
    this.alwaysScroll = false,
    this.gap = 42,
    this.speed = 26,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  /// Первый замер иногда происходит до того, как родитель окончательно
  /// разложил содержимое — например, внутри выдвижного листа. Тогда текст
  /// считался «влезающим» и оставался обрезанным. Один принудительный
  /// пересчёт после первого кадра это лечит.
  bool _remeasured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _remeasured = true);
    });
  }

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  /// Доля цикла, которую текст стоит на месте в начальной позиции — без этой
  /// паузы надпись читается хуже, чем едет.
  static const _hold = 0.14;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ensureRunning(double distance) {
    final ms = (distance / widget.speed * 1000 / (1 - _hold)).round().clamp(3000, 30000);
    if (_c.duration?.inMilliseconds == ms && _c.isAnimating) return;
    // Менять параметры контроллера прямо во время build нельзя, поэтому
    // откладываем до конца кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.duration = Duration(milliseconds: ms);
      _c.repeat();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      // _remeasured меняется после первого кадра и заставляет пересчитать
      // ширину по окончательной раскладке.
      key: ValueKey(_remeasured),
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final textWidth = painter.width;
        // Небольшой запас: если текст впритык, ехать незачем.
        if (!widget.alwaysScroll && (!box.hasBoundedWidth || textWidth <= box.maxWidth - 4)) {
          if (_c.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _c.stop();
            });
          }
          return Text(
            widget.text,
            style: style,
            textAlign: widget.align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final distance = textWidth + widget.gap;
        _ensureRunning(distance);

        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final progress = t <= _hold ? 0.0 : (t - _hold) / (1 - _hold);
                return OverflowBox(
                  maxWidth: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(-distance * progress, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.text, style: style, maxLines: 1, softWrap: false),
                        SizedBox(width: widget.gap),
                        Text(widget.text, style: style, maxLines: 1, softWrap: false),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
