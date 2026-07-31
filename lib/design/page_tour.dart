import 'package:flutter/material.dart';

import '../services/tour_service.dart';
import 'tokens.dart';

/// Шаг обучения по одной странице.
class PageTourStep {
  /// Имя места на этой же странице — такое же передаётся в [TourSpot].
  final String anchor;
  final String title;
  final String text;

  const PageTourStep({required this.anchor, required this.title, required this.text});
}

/// Сообщает вложенным виджетам, видна ли страница прямо сейчас.
///
/// Вкладки внутри `IndexedStack` строятся все сразу, поэтому «страница
/// открыта» и «страница построена» — разные вещи. Обучение должно
/// запускаться по первому, а не по второму.
class TourVisibility extends InheritedWidget {
  final bool visible;

  const TourVisibility({super.key, required this.visible, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourVisibility>()?.visible ?? true;

  @override
  bool updateShouldNotify(TourVisibility oldWidget) => oldWidget.visible != visible;
}

/// Обучение по одной странице: запускается при первом заходе на неё и больше
/// не повторяется. Никаких переходов между экранами — каждая страница
/// рассказывает про себя сама.
class PageTour extends StatefulWidget {
  /// Имя страницы для отметки «уже показывали».
  final String pageId;
  final List<PageTourStep> steps;
  final Widget child;

  const PageTour({
    super.key,
    required this.pageId,
    required this.steps,
    required this.child,
  });

  @override
  State<PageTour> createState() => PageTourState();

  /// Ближайшее обучение вверх по дереву — через него [TourSpot] себя
  /// регистрирует.
  static PageTourState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<PageTourState>();
}

class PageTourState extends State<PageTour> {
  final Map<String, GlobalKey> _anchors = {};
  bool _active = false;
  int _index = 0;
  bool _startScheduled = false;

  void register(String id, GlobalKey key) => _anchors[id] = key;

  void unregister(String id, GlobalKey key) {
    if (_anchors[id] == key) _anchors.remove(id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TourVisibility.of(context);
    if (!visible || _active || _startScheduled) return;
    if (TourService.isDone(widget.pageId)) return;

    _startScheduled = true;
    // Ждём кадр: на момент первой сборки виджеты ещё не разложены и их
    // положение неизвестно.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _index = _firstAvailableFrom(0);
        _active = _index < widget.steps.length;
      });
      if (!_active) TourService.markDone(widget.pageId);
    });
  }

  /// Первый шаг, чьё место реально есть на экране. Пропускаем то, чего у
  /// пользователя пока нет: у нового аккаунта нет ни бумаг, ни сделок, и
  /// обучение не должно упираться в пустоту.
  int _firstAvailableFrom(int start) {
    for (int i = start; i < widget.steps.length; i++) {
      if (_rectFor(widget.steps[i].anchor) != null) return i;
    }
    return widget.steps.length;
  }

  /// Положение места в координатах САМОГО обучения, а не экрана.
  ///
  /// Подсветка живёт внутри страницы, а `localToGlobal` даёт координаты от
  /// верха экрана. Из-за этой разницы вырез и подсказка съезжали вниз ровно на
  /// высоту всего, что выше страницы, — и кнопки уезжали за нижний край.
  Rect? _rectFor(String id) {
    final key = _anchors[id];
    final anchorContext = key?.currentContext;
    if (anchorContext == null) return null;
    final box = anchorContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;

    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize || !self.attached) return null;

    final topLeft = self.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = topLeft & box.size;
    if (rect.width <= 0 || rect.height <= 0) return null;

    // Место может быть прокручено за пределы страницы — подсвечивать нечего.
    final bounds = Offset.zero & self.size;
    if (!bounds.overlaps(rect)) return null;
    return rect;
  }

  Future<void> _finish() async {
    setState(() => _active = false);
    await TourService.markDone(widget.pageId);
  }

  void _next() {
    final next = _firstAvailableFrom(_index + 1);
    if (next >= widget.steps.length) {
      _finish();
      return;
    }
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;

    // Пересчитываем положение подсветки после каждого кадра: страница могла
    // прокрутиться или перестроиться.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active) setState(() {});
    });

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: _Spotlight(
            rect: _rectFor(widget.steps[_index].anchor),
            step: widget.steps[_index],
            index: _index,
            total: widget.steps.length,
            onNext: _next,
            onSkip: _finish,
          ),
        ),
      ],
    );
  }
}

/// Место на странице, которое умеет подсвечиваться обучением.
class TourSpot extends StatefulWidget {
  final String id;
  final Widget child;

  const TourSpot({super.key, required this.id, required this.child});

  @override
  State<TourSpot> createState() => _TourSpotState();
}

class _TourSpotState extends State<TourSpot> {
  final GlobalKey _key = GlobalKey();
  PageTourState? _tour;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tour ??= PageTour.maybeOf(context)?..register(widget.id, _key);
  }

  @override
  void dispose() {
    _tour?.unregister(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

class _Spotlight extends StatelessWidget {
  final Rect? rect;
  final PageTourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Spotlight({
    required this.rect,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  static const _pad = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) => _build(context, Size(box.maxWidth, box.maxHeight)));
  }

  Widget _build(BuildContext context, Size size) {
    final hole = rect == null
        ? null
        : Rect.fromLTRB(
            (rect!.left - _pad).clamp(0.0, size.width),
            (rect!.top - _pad).clamp(0.0, size.height),
            (rect!.right + _pad).clamp(0.0, size.width),
            (rect!.bottom + _pad).clamp(0.0, size.height),
          );

    return Stack(
      children: [
        // Затемнение с вырезом. Пока идёт обучение, страница не реагирует на
        // нажатия и прокрутку — работают только кнопки в подсказке.
        Positioned.fill(
          child: AbsorbPointer(
            child: CustomPaint(painter: _SpotlightPainter(hole: hole)),
          ),
        ),
        _bubble(context, size, hole),
      ],
    );
  }

  Widget _bubble(BuildContext context, Size size, Rect? hole) {
    final accent = context.accent;
    // Подсказку ставим с той стороны выреза, где больше места, и не даём ей
    // уехать за край страницы — иначе до кнопок не дотянуться.
    const bubbleHeight = 210.0;
    final below = hole == null || hole.center.dy < size.height / 2;
    final top = hole == null
        ? (size.height - bubbleHeight) / 2
        : below
            ? (hole.bottom + 16).clamp(0.0, (size.height - bubbleHeight).clamp(0.0, size.height))
            : null;
    final bottom = hole == null || below
        ? null
        : (size.height - hole.top + 16).clamp(0.0, (size.height - bubbleHeight).clamp(0.0, size.height));

    return Positioned(
      left: 18,
      right: 18,
      top: top,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
          decoration: BoxDecoration(
            color: context.isDark ? AppColors.darkSurfaceHigh : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: accent.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 30, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${index + 1} из $total',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: accent),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onSkip,
                    child: Text('Пропустить', style: TextStyle(fontSize: 11.5, color: context.dim)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(step.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(step.text, style: TextStyle(fontSize: 12.8, height: 1.45, color: context.dim)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onNext,
                  child: Text(index == total - 1 ? 'Понятно' : 'Дальше'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;

  const _SpotlightPainter({required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withOpacity(0.74);
    final screen = Rect.fromLTWH(0, 0, size.width, size.height);

    if (hole == null) {
      canvas.drawRect(screen, dim);
      return;
    }

    final rounded = RRect.fromRectAndRadius(hole!, const Radius.circular(18));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addRRect(rounded),
      ),
      dim,
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}
