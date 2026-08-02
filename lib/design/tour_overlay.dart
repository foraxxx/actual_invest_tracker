import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/tour_service.dart';

/// Шаг обучения: что подсветить и что рассказать.
class TourStep {
  /// Идентификатор места на экране. Ровно такой же передаётся в [TourAnchor].
  final String anchor;
  final String title;
  final String text;

  /// Шаг проходится действием пользователя — например, тапом по подсвеченной
  /// кнопке. Кнопки «Дальше» тогда нет: смысл в том, чтобы человек нажал сам.
  final bool requiresTap;

  const TourStep({
    required this.anchor,
    required this.title,
    required this.text,
    this.requiresTap = false,
  });
}

/// Область, которая может быть не видна пользователю, хотя и построена.
///
/// Вкладки внутри `IndexedStack` строятся все сразу: поиск на «Бирже»
/// существует и имеет размер, даже когда открыт «Портфель». Без этой пометки
/// обучение считало такие места видимыми и перескакивало вперёд, не дождавшись
/// нажатия.
class TourScope extends InheritedWidget {
  final bool active;

  const TourScope({super.key, required this.active, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourScope>()?.active ?? true;

  @override
  bool updateShouldNotify(TourScope oldWidget) => oldWidget.active != active;
}

/// Обёртка вокруг любого виджета, который умеет подсвечивать обучение.
/// Регистрирует свой ключ по имени — оверлей по нему находит место на экране.
class TourAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const TourAnchor({super.key, required this.id, required this.child});

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  final GlobalKey _key = GlobalKey();
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(TourScope.of(context));
  }

  void _sync(bool active) {
    if (active == _registered) return;
    _registered = active;
    if (active) {
      TourController.instance.register(widget.id, _key);
    } else {
      TourController.instance.unregister(widget.id, _key);
    }
  }

  @override
  void dispose() {
    if (_registered) TourController.instance.unregister(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

/// Управляет обучением: хранит порядок шагов, знает, какие места сейчас есть
/// на экране, и двигает шаг вперёд.
///
/// Ключевая идея: шаг с [TourStep.requiresTap] не переключается кнопкой —
/// он ждёт, пока на экране появится место из следующего шага. Пользователь
/// нажимает подсвеченную кнопку, приложение переходит на другой экран, там
/// регистрируется следующий якорь — и подсказка едет за ним.
class TourController extends ChangeNotifier {
  TourController._();

  static final TourController instance = TourController._();

  static const steps = <TourStep>[
    TourStep(
      anchor: 'portfolio_card',
      title: 'Портфели',
      text: 'Каждый портфель — отдельная история сделок, выплат и планов. '
          'Нажмите на портфель, чтобы открыть его.',
      requiresTap: true,
    ),
    TourStep(
      anchor: 'dashboard_hero',
      title: 'Стоимость и прибыль',
      text: 'Сколько сейчас стоят бумаги и сколько Вы на них заработали. '
          'График показывает, как менялась стоимость портфеля.',
    ),
    TourStep(
      anchor: 'dashboard_invested',
      title: 'Вложено своих',
      text: 'Только Ваши деньги, поступившие извне. Пополнения приложение считает по сделкам: '
          'продажа и новая покупка не увеличивают вложенную сумму. Нажмите, чтобы открыть счёт.',
    ),
    TourStep(
      anchor: 'dashboard_cash',
      title: 'Свободные деньги',
      text: 'Деньги на счёте, ещё не вложенные в бумаги. Если Вы сняли их у брокера — '
          'запишите вывод здесь, иначе следующая покупка спишется с них.',
    ),
    TourStep(
      anchor: 'nav_market',
      title: 'Биржа',
      text: 'Все бумаги Мосбиржи с котировками, курсы валют и графики. Откройте этот раздел.',
      requiresTap: true,
    ),
    TourStep(
      anchor: 'market_search',
      title: 'Поиск и фильтры',
      text: 'Найдите бумагу по тикеру или названию, отфильтруйте по типу. '
          'Тап по строке открывает карточку — купить можно прямо оттуда.',
    ),
    TourStep(
      anchor: 'nav_settings',
      title: 'Настройки',
      text: 'Загрузка с биржи, оформление, резервные копии и это обучение. Откройте раздел.',
      requiresTap: true,
    ),
    TourStep(
      anchor: 'settings_online',
      title: 'Биржа и котировки',
      text: 'Здесь включается загрузка с Мосбиржи: котировки, курсы валют, отрасли и логотипы. '
          'Без неё приложение работает полностью офлайн.',
    ),
    TourStep(
      anchor: 'settings_data',
      title: 'Резервные копии',
      text: 'Данные лежат только на телефоне, поэтому бэкап — единственная страховка. '
          'Здесь же включается автосохранение в папку. На этом всё!',
    ),
  ];

  final Map<String, List<GlobalKey>> _anchors = {};
  bool _active = false;
  int _index = 0;

  bool get active => _active;
  int get index => _index;
  TourStep get step => steps[_index];
  int get total => steps.length;

  void register(String id, GlobalKey key) {
    _anchors.putIfAbsent(id, () => []).add(key);
    if (_active) _scheduleNotify();
  }

  void unregister(String id, GlobalKey key) {
    _anchors[id]?.remove(key);
    if (_active) _scheduleNotify();
  }

  void _scheduleNotify() {
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  void start() {
    _index = 0;
    _active = true;
    _scheduleNotify();
    notifyListeners();
  }

  Future<void> finish() async {
    _active = false;
    await TourService.setCompleted(true);
    notifyListeners();
  }

  void next() {
    if (_index >= steps.length - 1) {
      finish();
      return;
    }
    _index++;
    _scheduleNotify();
    notifyListeners();
  }

  /// Прямоугольник подсвечиваемого места на экране, если оно сейчас есть.
  ///
  /// Учитываются только якоря на текущем экране: предыдущий экран остаётся в
  /// дереве под новым, и без этой проверки подсветка продолжала показывать
  /// место с него — вырез висел поверх нового экрана и пропускал нажатия куда
  /// попало.
  Rect? rectFor(String id) {
    for (final key in _anchors[id] ?? const <GlobalKey>[]) {
      final context = key.currentContext;
      if (context == null) continue;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final offset = box.localToGlobal(Offset.zero);
      final rect = offset & box.size;
      if (rect.width <= 0 || rect.height <= 0) continue;
      return rect;
    }
    return null;
  }

  /// Не пора ли перескочить дальше: пользователь нажал подсвеченную кнопку и
  /// на экране появилось место следующего шага.
  void syncWithScreen() {
    if (!_active) return;
    if (!step.requiresTap) return;
    if (_index >= steps.length - 1) return;
    if (rectFor(steps[_index + 1].anchor) != null) {
      _index++;
      _scheduleNotify();
      notifyListeners();
    }
  }
}

/// Слой подсветки поверх всего приложения. Ставится один раз в `MaterialApp`.
class TourOverlay extends StatefulWidget {
  final Widget child;

  const TourOverlay({super.key, required this.child});

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  final _controller = TourController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.active) return widget.child;

    // Пересчитываем положение после каждого кадра: экран мог прокрутиться,
    // клавиатура открыться, а подсветка должна оставаться на месте.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.syncWithScreen();
      setState(() {});
    });

    final rect = _controller.rectFor(_controller.step.anchor);

    return Stack(
      children: [
        widget.child,
        // Пока идёт обучение, системная кнопка «назад» не уводит с экрана:
        // иначе последовательность шагов рассыпается.
        const Positioned.fill(child: PopScope(canPop: false, child: SizedBox.shrink())),
        Positioned.fill(
          child: _Spotlight(
            rect: rect,
            step: _controller.step,
            index: _controller.index,
            total: _controller.total,
            onNext: _controller.next,
            onSkip: _controller.finish,
          ),
        ),
      ],
    );
  }
}

class _Spotlight extends StatelessWidget {
  final Rect? rect;
  final TourStep step;
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

  static const _padding = 8.0;
  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hole = rect == null
        ? null
        : Rect.fromLTRB(
            (rect!.left - _padding).clamp(0.0, size.width),
            (rect!.top - _padding).clamp(0.0, size.height),
            (rect!.right + _padding).clamp(0.0, size.width),
            (rect!.bottom + _padding).clamp(0.0, size.height),
          );

    return Stack(
      children: [
        // Затемнение с вырезом — не перехватывает нажатия само по себе.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _SpotlightPainter(hole: hole, radius: _radius)),
          ),
        ),

        // Нажатия блокируются везде, КРОМЕ выреза: подсвеченную кнопку можно
        // нажать по-настоящему, всё остальное — нет.
        if (hole != null) ...[
          _blocker(left: 0, top: 0, width: size.width, height: hole.top),
          _blocker(left: 0, top: hole.bottom, width: size.width, height: size.height - hole.bottom),
          _blocker(left: 0, top: hole.top, width: hole.left, height: hole.height),
          _blocker(
            left: hole.right,
            top: hole.top,
            width: size.width - hole.right,
            height: hole.height,
          ),
        ] else
          Positioned.fill(child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque)),

        _bubble(context, size, hole),
      ],
    );
  }

  Widget _blocker({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: width < 0 ? 0 : width,
      height: height < 0 ? 0 : height,
      // AbsorbPointer съедает любые жесты, включая прокрутку и свайпы:
      // во время обучения работать должно только подсвеченное место.
      child: const AbsorbPointer(
        child: SizedBox.expand(child: ColoredBox(color: Color(0x01000000))),
      ),
    );
  }

  Widget _bubble(BuildContext context, Size size, Rect? hole) {
    final accent = context.accent;
    // Подсказку ставим с той стороны выреза, где больше места.
    final below = hole == null || hole.center.dy < size.height / 2;
    final top = hole == null
        ? size.height * 0.32
        : below
            ? hole.bottom + 18
            : null;
    final bottom = hole == null || below ? null : size.height - hole.top + 18;

    return Positioned(
      left: 20,
      right: 20,
      top: top,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: context.isDark ? AppColors.darkSurfaceHigh : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: accent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 28, offset: const Offset(0, 10)),
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
                    child: Text(
                      'Пропустить',
                      style: TextStyle(fontSize: 11.5, color: context.dim),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(step.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(step.text, style: TextStyle(fontSize: 13, height: 1.45, color: context.dim)),
              const SizedBox(height: 12),
              if (step.requiresTap && hole != null)
                Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 16, color: accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Нажмите на подсвеченное место',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: accent),
                      ),
                    ),
                  ],
                )
              // Если места на экране нет — например, у нового пользователя ещё
              // нет ни одного портфеля, — тур не должен вставать колом:
              // показываем кнопку и идём дальше.
              else if (hole == null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Этого пока нет на экране',
                        style: TextStyle(fontSize: 11.5, color: context.dim),
                      ),
                    ),
                    FilledButton(
                      onPressed: onNext,
                      child: Text(index == total - 1 ? 'Готово' : 'Дальше'),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: onNext,
                    child: Text(index == total - 1 ? 'Готово' : 'Дальше'),
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
  final double radius;

  const _SpotlightPainter({required this.hole, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withOpacity(0.76);
    final screen = Rect.fromLTWH(0, 0, size.width, size.height);

    if (hole == null) {
      canvas.drawRect(screen, dim);
      return;
    }

    final rounded = RRect.fromRectAndRadius(hole!, Radius.circular(radius));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(screen),
      Path()..addRRect(rounded),
    );
    canvas.drawPath(path, dim);

    // Светящаяся рамка вокруг выреза — чтобы взгляд сразу цеплялся.
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}
