import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

// =============================================================================
// СПАРКЛАЙН
// =============================================================================

/// Плавная линия стоимости с градиентной заливкой, неоновым свечением и
/// «прокруткой» пальцем: при ведении по графику подсвечивается конкретная
/// точка, показывается её значение и даётся лёгкая тактильная отдача.
///
/// Написан на CustomPaint вместо готовой библиотеки — так линия рисуется
/// анимированно (прочерчивается слева направо при появлении) и свечение
/// выглядит именно так, как задумано.
/// Отметка на линии графика — например, сделка в этот день.
class SparkMarker {
  /// Номер точки графика, к которой привязана отметка.
  final int index;
  final Color color;

  const SparkMarker({required this.index, required this.color});
}

/// Диапазон, за который показывается график.
enum ChartRange { day, week, month, year, fiveYears, all }

extension ChartRangeX on ChartRange {
  String get label => switch (this) {
        ChartRange.day => 'День',
        ChartRange.week => 'Неделя',
        ChartRange.month => 'Месяц',
        ChartRange.year => 'Год',
        ChartRange.fiveYears => '5 лет',
        ChartRange.all => 'Всё время',
      };

  DateTime get from => switch (this) {
        // Именно сегодняшняя полночь: раньше брались двое суток назад, и на
        // графике «День» оказывались ещё позавчерашние торги.
        ChartRange.day => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        ChartRange.week => DateTime.now().subtract(const Duration(days: 7)),
        ChartRange.month => DateTime.now().subtract(const Duration(days: 31)),
        ChartRange.year => DateTime.now().subtract(const Duration(days: 365)),
        ChartRange.fiveYears => DateTime.now().subtract(const Duration(days: 365 * 5)),
        ChartRange.all => DateTime(1990),
      };

  /// Интервал свечи подбирается под диапазон: за день нужны минуты, за пять
  /// лет — недели, иначе точек либо слишком мало, либо десятки тысяч.
  int get interval => switch (this) {
        ChartRange.day => 10,
        ChartRange.week => 60,
        ChartRange.month => 24,
        ChartRange.year => 24,
        ChartRange.fiveYears => 7,
        ChartRange.all => 31,
      };

  /// Для «Дня» биржа может ничего не отдать: выходной или торги ещё не
  /// начались. Тогда имеет смысл показать последнюю прошедшую сессию, а не
  /// пустой экран — за ней и ходим на несколько дней назад.
  DateTime get fallbackFrom => DateTime.now().subtract(const Duration(days: 6));

  /// Длина окна. У «всего времени» окна нет — прокручивать нечего.
  Duration? get span => switch (this) {
        ChartRange.day => const Duration(days: 1),
        ChartRange.week => const Duration(days: 7),
        ChartRange.month => const Duration(days: 31),
        ChartRange.year => const Duration(days: 365),
        ChartRange.fiveYears => const Duration(days: 365 * 5),
        ChartRange.all => null,
      };

  bool get scrollable => span != null;

  int get maxRows => switch (this) {
        ChartRange.day => 1000,
        ChartRange.week => 1000,
        ChartRange.month => 1000,
        ChartRange.year => 2000,
        ChartRange.fiveYears => 2000,
        ChartRange.all => 2000,
      };

  /// Во сколько раз грузим больше выбранного периода — это запас для листания.
  /// Пять окон влево-вправо хватает, чтобы прокрутка не упиралась в край на
  /// первом же движении.
  int get bufferFactor => scrollable ? 5 : 1;

  /// Левая граница загрузки с запасом.
  DateTime get bufferFrom {
    final s = span;
    if (s == null) return from;
    return DateTime.now().subtract(s * bufferFactor);
  }

  /// Левая календарная граница окна, оканчивающегося в [anchor]. В отличие от
  /// деления массива точек на части, выходные и пропуски торгов не меняют период.
  DateTime windowFrom(DateTime anchor) => switch (this) {
        ChartRange.day => anchor.subtract(const Duration(days: 1)),
        ChartRange.week => anchor.subtract(const Duration(days: 7)),
        ChartRange.month => _calendarBack(anchor, months: 1),
        ChartRange.year => _calendarBack(anchor, years: 1),
        ChartRange.fiveYears => _calendarBack(anchor, years: 5),
        ChartRange.all => DateTime(1990),
      };

  static DateTime _calendarBack(DateTime value, {int months = 0, int years = 0}) {
    final targetMonth = value.month - months;
    final normalized = DateTime(value.year - years, targetMonth, 1);
    final lastDay = DateTime(normalized.year, normalized.month + 1, 0).day;
    return DateTime(
      normalized.year,
      normalized.month,
      math.min(value.day, lastDay),
      value.hour,
      value.minute,
      value.second,
    );
  }
}

class ChartWindow {
  final int start;
  final int size;

  const ChartWindow({required this.start, required this.size});
}

/// Находит окно выбранной календарной длины, привязанное к последней котировке.
ChartWindow chartWindowForDates(List<DateTime> dates, ChartRange range) {
  if (dates.isEmpty) return const ChartWindow(start: 0, size: 0);
  if (range == ChartRange.all) return ChartWindow(start: 0, size: dates.length);
  final from = range.windowFrom(dates.last);
  var start = dates.indexWhere((date) => !date.isBefore(from));
  if (start < 0) start = math.max(0, dates.length - 1);
  return ChartWindow(start: start, size: dates.length - start);
}


class Sparkline extends StatefulWidget {
  final List<double> values;
  final Color color;
  final double height;
  final bool fill;
  final bool interactive;
  final String Function(int index, double value)? tooltipBuilder;

  /// Подпись даты для точки — нужна для замера двумя пальцами.
  final String Function(int index)? dateLabel;

  /// Как показывать цену в окне замера.
  final String Function(double value)? priceLabel;

  /// Отметки на линии — сделки по бумаге.
  final List<SparkMarker> markers;

  /// Что показать при нажатии на отметку сделки. Строки разделяются \n.
  final String Function(int index)? markerLabel;

  /// Сколько точек видно одновременно. null — рисуем весь набор.
  final int? windowSize;

  /// Индекс левой видимой точки. Дробный — за счёт этого линия едет плавно,
  /// а не прыгает от точки к точке.
  final double windowStart;

  /// Пользователь тянет график: сдвиг в точках графика (уже пересчитанный из
  /// пикселей). Экран двигает окно и перерисовывает те же данные — ничего не
  /// загружается, поэтому движение получается непрерывным.
  final void Function(double deltaPoints)? onPan;

  /// Жест закончился — можно, например, догрузить историю.
  final VoidCallback? onPanEnd;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 140,
    this.fill = true,
    this.interactive = true,
    this.tooltipBuilder,
    this.dateLabel,
    this.priceLabel,
    this.markers = const [],
    this.markerLabel,
    this.windowSize,
    this.windowStart = 0,
    this.onPan,
    this.onPanEnd,
  });

  @override
  State<Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<Sparkline> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppDuration.chart);
  int? _touch;

  /// Позиции всех прижатых пальцев. Считаем их сами через Listener: обычные
  /// жесты отдают только один указатель, а для замера нужны оба.
  final Map<int, double> _pointers = {};
  bool _multiTouchGesture = false;
  double _panDuringGesture = 0;
  Timer? _holdTimer;
  int? _primaryPointer;
  double _primaryDownX = 0;
  bool _trackingTouch = false;

  /// Отметка сделки, по которой нажали: её окно висит до следующего нажатия.
  int? _marker;

  /// Границы замера двумя пальцами — индексы точек графика.
  int? _rangeLeft;
  int? _rangeRight;

  bool get _measuring => _rangeLeft != null && _rangeRight != null;

  bool get _canScroll => widget.onPan != null;

  /// Сколько точек видно: либо заданное окно, либо весь набор.
  int get _visible {
    final size = widget.windowSize;
    if (size == null) return widget.values.length;
    return size.clamp(2, widget.values.length);
  }

  /// Ширина одной точки в пикселях.
  double _step(double width) => width / (_visible - 1);

  /// Индекс точки под пальцем — с поправкой на положение окна.
  int _indexAt(double dx, double width) {
    final raw = widget.windowStart + dx / _step(width);
    return raw.round().clamp(0, widget.values.length - 1);
  }

  void _syncRange(double width) {
    if (_pointers.length < 2) {
      if (_measuring) {
        setState(() {
          _rangeLeft = null;
          _rangeRight = null;
        });
      }
      return;
    }

    final xs = _pointers.values.toList()..sort();
    final left = _indexAt(xs.first, width);
    final right = _indexAt(xs.last, width);
    if (left != _rangeLeft || right != _rangeRight) {
      final started = !_measuring;
      setState(() {
        _rangeLeft = left;
        _rangeRight = right;
        _touch = null;
      });
      if (started) HapticFeedback.selectionClick();
    }
  }

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(covariant Sparkline old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _updateTouch(double dx, double width) {
    final n = widget.values.length;
    if (n < 2) return;
    final idx = _indexAt(dx, width);
    if (idx != _touch) {
      setState(() => _touch = idx);
      HapticFeedback.selectionClick();
    }
  }

  void _startTouchTracking(int pointer, double dx, double width) {
    _holdTimer?.cancel();
    _primaryPointer = pointer;
    _primaryDownX = dx;
    _trackingTouch = false;
    _holdTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _multiTouchGesture || _pointers.length != 1 || !_pointers.containsKey(pointer)) return;
      _trackingTouch = true;
      _updateTouch(_pointers[pointer]!, width);
    });
  }

  void _moveTouchTracking(int pointer, double dx, double width) {
    if (pointer != _primaryPointer) return;
    if (_trackingTouch) {
      _updateTouch(dx, width);
    } else if ((dx - _primaryDownX).abs() > 10) {
      _holdTimer?.cancel();
    }
  }

  void _stopTouchTracking(int pointer) {
    if (pointer != _primaryPointer) return;
    _holdTimer?.cancel();
    _primaryPointer = null;
    if (_trackingTouch || _touch != null) {
      _trackingTouch = false;
      if (mounted) setState(() => _touch = null);
    }
  }

  /// Отметка сделки рядом с точкой нажатия. Ищем по расстоянию в пикселях, а
  /// не по индексу: на длинном периоде одна точка графика — это несколько
  /// дней, и попасть пальцем ровно в неё нельзя.
  int? _markerNear(double dx, double width) {
    if (widget.markers.isEmpty || widget.values.length < 2) return null;
    final step = _step(width);
    int? best;
    double bestDistance = 22;
    for (final m in widget.markers) {
      if (m.index < 0 || m.index >= widget.values.length) continue;
      final distance = ((m.index - widget.windowStart) * step - dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = m.index;
      }
    }
    return best;
  }

  void _handleTap(double dx, double width) {
    final marker = _markerNear(dx, width);
    setState(() {
      _touch = null;
      // Повторное нажатие по той же отметке закрывает окно.
      _marker = (marker != null && marker != _marker) ? marker : null;
    });
    if (marker != null) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    if (values.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Мало данных для графика',
            style: TextStyle(fontSize: 12, color: context.dim),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final touchedX =
            _touch == null ? 0.0 : (_touch! - widget.windowStart) * _step(w);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.interactive
              ? (e) {
                  if (_pointers.isEmpty) {
                    _panDuringGesture = 0;
                    _startTouchTracking(e.pointer, e.localPosition.dx, w);
                  }
                  _pointers[e.pointer] = e.localPosition.dx;
                  if (_pointers.length >= 2) {
                    _holdTimer?.cancel();
                    _trackingTouch = false;
                    if (_touch != null) setState(() => _touch = null);
                    _multiTouchGesture = true;
                    // Если первый палец успел чуть сдвинуть окно до появления
                    // второго, возвращаем график на исходное место.
                    if (_panDuringGesture != 0 && widget.onPan != null) {
                      widget.onPan!(-_panDuringGesture);
                      _panDuringGesture = 0;
                    }
                  }
                  _syncRange(w);
                }
              : null,
          onPointerMove: widget.interactive
              ? (e) {
                  _pointers[e.pointer] = e.localPosition.dx;
                  _moveTouchTracking(e.pointer, e.localPosition.dx, w);
                  _syncRange(w);
                }
              : null,
          onPointerUp: widget.interactive
              ? (e) {
                  _stopTouchTracking(e.pointer);
                  _pointers.remove(e.pointer);
                  _syncRange(w);
                  if (_pointers.isEmpty) {
                    Future.microtask(() => _multiTouchGesture = false);
                  }
                }
              : null,
          onPointerCancel: widget.interactive
              ? (e) {
                  _stopTouchTracking(e.pointer);
                  _pointers.remove(e.pointer);
                  _syncRange(w);
                  if (_pointers.isEmpty) {
                    Future.microtask(() => _multiTouchGesture = false);
                  }
                }
              : null,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Перетаскивание листает период — но только если экран это разрешил.
          // Тянем — окно едет вместе с пальцем, точка в точку.
          onHorizontalDragUpdate:
              _canScroll
                  ? (d) {
                      if (_multiTouchGesture || _pointers.length >= 2 || _trackingTouch) return;
                      final delta = -d.delta.dx / _step(w);
                      _panDuringGesture += delta;
                      widget.onPan!(delta);
                    }
                  : null,
          onHorizontalDragEnd: _canScroll
              ? (_) {
                  if (!_multiTouchGesture) widget.onPanEnd?.call();
                }
              : null,
          // Удержание обрабатывает Listener выше и больше не проигрывает
          // горизонтальному drag-жесту при небольшом движении пальца.
          onTapDown: widget.interactive ? (d) => _updateTouch(d.localPosition.dx, w) : null,
          onTapUp: widget.interactive ? (d) => _handleTap(d.localPosition.dx, w) : null,
          onTapCancel: widget.interactive ? () => setState(() => _touch = null) : null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => CustomPaint(
                      painter: _SparklinePainter(
                        values: values,
                        color: widget.color,
                        progress: Curves.easeOutCubic.transform(_c.value),
                        fill: widget.fill,
                        touchIndex: _touch,
                        markers: widget.markers,
                        windowStart: widget.windowStart,
                        windowSize: _visible,
                        rangeLeft: _rangeLeft,
                        rangeRight: _rangeRight,
                        selectedMarker: _marker,
                      ),
                    ),
                  ),
                ),
                if (_touch != null && !_measuring)
                  Positioned(
                    // Окно шире, чем раньше: в него должна влезать дата со
                    // временем целиком.
                    left: (touchedX - 70).clamp(0.0, math.max(0.0, w - 140)),
                    top: 0,
                    child: _Tooltip(
                      text: widget.tooltipBuilder?.call(_touch!, values[_touch!]) ??
                          values[_touch!].toStringAsFixed(0),
                      color: widget.color,
                    ),
                  ),
                if (_marker != null && !_measuring && widget.markerLabel != null)
                  Positioned(
                    left: ((_marker! - widget.windowStart) * _step(w) - 80)
                        .clamp(0.0, math.max(0.0, w - 160)),
                    bottom: 8,
                    child: _Tooltip(
                      text: widget.markerLabel!(_marker!),
                      color: widget.markers
                              .firstWhere((m) => m.index == _marker,
                                  orElse: () => SparkMarker(index: _marker!, color: widget.color))
                              .color,
                    ),
                  ),
                if (_measuring)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Center(
                      child: _RangeBox(
                        color: widget.color,
                        fromValue: values[_rangeLeft!],
                        toValue: values[_rangeRight!],
                        fromLabel: widget.dateLabel?.call(_rangeLeft!) ?? '',
                        toLabel: widget.dateLabel?.call(_rangeRight!) ?? '',
                        priceLabel: widget.priceLabel ?? (v) => v.toStringAsFixed(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}


/// Окно замера: цена и дата под каждым пальцем плюс разница между ними.
class _RangeBox extends StatelessWidget {
  final Color color;
  final double fromValue;
  final double toValue;
  final String fromLabel;
  final String toLabel;
  final String Function(double) priceLabel;

  const _RangeBox({
    required this.color,
    required this.fromValue,
    required this.toValue,
    required this.fromLabel,
    required this.toLabel,
    required this.priceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final diff = toValue - fromValue;
    final pct = fromValue == 0 ? 0.0 : diff / fromValue.abs() * 100;
    final diffColor = AppColors.pnl(diff);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.darkSurfaceTop : Colors.white,
        borderRadius: BorderRadius.circular(12),
        // Рамка по направлению изменения: вырос — зелёная, упал — красная.
        border: Border.all(color: diffColor.withOpacity(0.6), width: 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _side(context, fromLabel, priceLabel(fromValue)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: context.dim),
              ),
              _side(context, toLabel, priceLabel(toValue)),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: diffColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${diff >= 0 ? '+' : ''}${priceLabel(diff)}   ${diff >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: diffColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _side(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text(label, style: TextStyle(fontSize: 9.5, color: context.dim)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Tooltip extends StatelessWidget {
  final String text;
  final Color color;

  const _Tooltip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    // Каждая строка — отдельный Text без переносов. Раньше это был один Text с
    // \n и ограничением в две строки: длинная дата со временем занимала обе,
    // и значение до экрана не доходило.
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.darkSurfaceTop : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.45)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 14)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < lines.length; i++)
            Text(
              lines[i],
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                // Первая строка — когда, остальные — сколько.
                fontSize: i == 0 ? 10.5 : 12.5,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w800,
                color: i == 0 ? context.dim : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double progress;
  final bool fill;
  final int? touchIndex;
  final List<SparkMarker> markers;
  final int? rangeLeft;
  final int? rangeRight;
  final int? selectedMarker;
  final double windowStart;
  final int windowSize;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.progress,
    required this.fill,
    this.touchIndex,
    this.markers = const [],
    this.rangeLeft,
    this.rangeRight,
    this.selectedMarker,
    this.windowStart = 0,
    required this.windowSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    // Окно просмотра: рисуем не весь набор, а видимый отрезок. Масштаб по
    // вертикали тоже считается по нему — иначе при листании линия выглядела бы
    // плоской, потому что диапазон брался по всем загруженным данным.
    final visible = windowSize.clamp(2, values.length);
    final firstVisible = windowStart.floor().clamp(0, values.length - 1);
    final lastVisible = (windowStart + visible).ceil().clamp(0, values.length - 1);

    double minV = values[firstVisible];
    double maxV = values[firstVisible];
    for (int i = firstVisible; i <= lastVisible; i++) {
      final v = values[i];
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    // Плоская линия (все значения равны) не должна схлопываться в ноль
    // высоты — раздвигаем диапазон искусственно и рисуем её посередине.
    if ((maxV - minV).abs() < 1e-9) {
      minV -= 1;
      maxV += 1;
    }

    const padTop = 14.0;
    const padBottom = 8.0;
    final usable = size.height - padTop - padBottom;

    // Шаг между точками — по видимому окну, а положение точки отсчитывается от
    // его левого края. Соседние точки за краями тоже считаем: линия должна
    // входить в экран и выходить из него, а не обрываться.
    final step = size.width / (visible - 1);
    final points = <Offset>[];
    final indices = <int>[];
    for (int i = math.max(0, firstVisible - 1);
        i <= math.min(values.length - 1, lastVisible + 1);
        i++) {
      final x = (i - windowStart) * step;
      final norm = (values[i] - minV) / (maxV - minV);
      points.add(Offset(x, padTop + (1 - norm) * usable));
      indices.add(i);
    }
    if (points.length < 2) return;

    /// Точка по абсолютному индексу значения. Список точек теперь частичный —
    /// только видимое окно, поэтому обращаться к нему по индексу значения
    /// нельзя.
    Offset? pointAt(int index) {
      final at = indices.indexOf(index);
      if (at >= 0) return points[at];
      if (index < 0 || index >= values.length) return null;
      // Точка за пределами окна — считаем её положение по той же формуле.
      final norm = (values[index] - minV) / (maxV - minV);
      return Offset((index - windowStart) * step, padTop + (1 - norm) * usable);
    }

    // За пределы карточки линия и заливка не выходят.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Сглаживание через квадратичные кривые по серединам отрезков — линия
    // получается мягкой, но не «уезжает» за пределы реальных значений, как
    // это делают кубические сплайны на резких скачках.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      line.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    // Частичный путь для анимации «прочерчивания»
    final drawn = Path();
    for (final metric in line.computeMetrics()) {
      drawn.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
    }

    if (fill) {
      final cutX = size.width * progress;
      final area = Path.from(drawn)
        ..lineTo(cutX, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.32), color.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(area, areaPaint);
    }

    // Свечение под линией
    final glow = Paint()
      ..color = color.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    canvas.drawPath(drawn, glow);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(drawn, stroke);

    // Точка на конце линии — «где мы сейчас»
    if (progress > 0.98) {
      final last = points.last;
      canvas.drawCircle(last, 8, Paint()..color = color.withOpacity(0.22));
      canvas.drawCircle(last, 4, Paint()..color = color);
      canvas.drawCircle(last, 1.8, Paint()..color = Colors.white);
    }

    // Отметки сделок: рисуем после линии, чтобы они были поверх, но до
    // подсветки пальца — она всегда должна оставаться заметнее всего.
    if (progress > 0.98) {
      for (final m in markers) {
        final p = pointAt(m.index);
        // Отметку вне видимого окна не рисуем.
        if (p == null || p.dx < -12 || p.dx > size.width + 12) continue;
        final selected = m.index == selectedMarker;
        // Вертикальных линий до низа больше нет — они забивали график. Осталась
        // сама точка, а выбранная подсвечивается ореолом.
        if (selected) {
          canvas.drawCircle(p, 11, Paint()..color = m.color.withOpacity(0.22));
        }
        canvas.drawCircle(p, selected ? 6.5 : 5.5, Paint()..color = m.color.withOpacity(0.95));
        canvas.drawCircle(
          p,
          selected ? 6.5 : 5.5,
          Paint()
            ..color = Colors.white.withOpacity(0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2 : 1.6,
        );
      }
    }

    // Замер двумя пальцами: затемняем всё вне диапазона и ставим по вертикали
    // на каждой границе — так видно, между какими точками считается разница.
    if (rangeLeft != null && rangeRight != null) {
      final li = rangeLeft!.clamp(0, values.length - 1);
      final ri = rangeRight!.clamp(0, values.length - 1);
      final a = pointAt(li);
      final b = pointAt(ri);
      if (a == null || b == null) {
        canvas.restore();
        return;
      }
      // Замер окрашивается по направлению: цена выросла — зелёным, упала —
      // красным. Так итог заметен ещё до чтения чисел.
      final rangeColor = AppColors.pnl(values[ri] - values[li]);

      canvas.drawRect(
        Rect.fromLTRB(a.dx, 0, b.dx, size.height),
        Paint()..color = rangeColor.withOpacity(0.12),
      );

      for (final p in <Offset>[a, b]) {
        canvas.drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height),
          Paint()
            ..color = rangeColor.withOpacity(0.8)
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(p, 5, Paint()..color = rangeColor);
        canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = Colors.white.withOpacity(0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }

    // Подсветка точки под пальцем
    final touchPoint = touchIndex == null ? null : pointAt(touchIndex!);
    if (touchPoint != null) {
      final guide = Paint()
        ..color = color.withOpacity(0.35)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(touchPoint.dx, 0), Offset(touchPoint.dx, size.height), guide);
      canvas.drawCircle(touchPoint, 9, Paint()..color = color.withOpacity(0.25));
      canvas.drawCircle(touchPoint, 5, Paint()..color = color);
      canvas.drawCircle(touchPoint, 2.2, Paint()..color = Colors.white);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.progress != progress ||
      old.touchIndex != touchIndex ||
      old.color != color ||
      old.markers.length != markers.length ||
      old.rangeLeft != rangeLeft ||
      old.rangeRight != rangeRight ||
      old.selectedMarker != selectedMarker ||
      old.windowStart != windowStart ||
      old.windowSize != windowSize ||
      old.windowSize != windowSize ||
      old.values.length != values.length;
}

// =============================================================================
// КОЛЬЦЕВАЯ ДИАГРАММА
// =============================================================================

/// Пончик с анимированным раскрытием, выделением доли по тапу (и по клику
/// на легенду) и живым центром: пока ничего не выбрано — там общая сумма,
/// при выборе — название доли и её процент.
class DonutChart extends StatefulWidget {
  final Map<String, double> data;
  final double size;
  final String Function(double) valueFormatter;
  final String centerLabel;

  const DonutChart({
    super.key,
    required this.data,
    required this.valueFormatter,
    this.size = 210,
    this.centerLabel = 'Всего',
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: AppDuration.chart)..forward();
  late final AnimationController _select =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  int _selected = -1;

  @override
  void dispose() {
    _enter.dispose();
    _select.dispose();
    super.dispose();
  }

  void _select_(int i) {
    setState(() => _selected = _selected == i ? -1 : i);
    _select.forward(from: 0);
    HapticFeedback.selectionClick();
  }

  void _handleTap(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    final dist = v.distance;
    final outer = widget.size / 2;
    if (dist < outer * 0.42 || dist > outer) {
      if (_selected != -1) _select_(_selected);
      return;
    }
    double angle = math.atan2(v.dy, v.dx) + math.pi / 2; // отсчёт от «12 часов»
    if (angle < 0) angle += 2 * math.pi;

    final entries = widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return;
    double acc = 0;
    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / total) * 2 * math.pi;
      if (angle >= acc && angle < acc + sweep) {
        _select_(i);
        return;
      }
      acc += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);
    final sel = _selected >= 0 && _selected < entries.length ? entries[_selected] : null;

    return Column(
      children: [
        SizedBox(
          height: widget.size,
          width: widget.size,
          child: GestureDetector(
            onTapDown: (d) => _handleTap(d.localPosition),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_enter, _select]),
                  builder: (context, _) => CustomPaint(
                    size: Size.square(widget.size),
                    painter: _DonutPainter(
                      values: entries.map((e) => e.value).toList(),
                      progress: Curves.easeOutCubic.transform(_enter.value),
                      selected: _selected,
                      selectProgress: Curves.easeOutBack.transform(_select.value.clamp(0.0, 1.0)),
                      trackColor: context.isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.size * 0.22),
                  child: AnimatedSwitcher(
                    duration: AppDuration.fast,
                    child: Column(
                      key: ValueKey(_selected),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sel?.key ?? widget.centerLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.dim),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.valueFormatter(sel?.value ?? total),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                        ),
                        if (sel != null && total > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${(sel.value / total * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.chartAt(_selected),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (int i = 0; i < entries.length; i++)
              GestureDetector(
                onTap: () => _select_(i),
                child: AnimatedContainer(
                  duration: AppDuration.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _selected == i
                        ? AppColors.chartAt(i).withOpacity(0.18)
                        : (context.isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _selected == i ? AppColors.chartAt(i) : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.chartAt(i), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          entries[i].key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _selected == i ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        total > 0 ? '${(entries[i].value / total * 100).toStringAsFixed(0)}%' : '0%',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.dim),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final double progress;
  final int selected;
  final double selectProgress;
  final Color trackColor;

  _DonutPainter({
    required this.values,
    required this.progress,
    required this.selected,
    required this.selectProgress,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final thickness = outer * 0.26;
    final baseRadius = outer - thickness / 2 - 6;

    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );

    // Зазор между секторами постоянный в радианах и одинаковый для всех:
    // ровные промежутки читаются как единое кольцо, а разнобой сразу бросается
    // в глаза. Концы дуг прямые (butt) — скруглённые выступали за край дуги на
    // половину её толщины и съедали зазор тем сильнее, чем толще кольцо.
    const gap = 0.045;
    const minSweep = 0.02; // чтобы доля в полпроцента не исчезла совсем
    double start = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final full = (values[i] / total) * 2 * math.pi;
      if (full <= 0) continue;

      final isSel = i == selected;
      final radius = baseRadius + (isSel ? 5 * selectProgress : 0);
      final width = thickness + (isSel ? 6 * selectProgress : 0);
      final color = AppColors.chartAt(i);

      final from = start + gap / 2;
      final sweep = math.max(full - gap, minSweep) * progress;

      if (sweep > 0) {
        // Заливка — линейный градиент по всему кольцу, а не sweep-градиент по
        // сектору: у sweep-градиента отсчёт идёт от трёх часов, и на длинной
        // дуге он давал резкий стык там, где проходил через ноль.
        final shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppGradient.lighten(color, 0.12), color],
        ).createShader(Rect.fromCircle(center: center, radius: radius + width / 2));

        if (isSel) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            from,
            sweep,
            false,
            Paint()
              ..color = color.withOpacity(0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
          );
        }

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          from,
          sweep,
          false,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = width,
        );
      }

      start += full;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.selectProgress != selectProgress ||
      old.values.length != values.length;
}

// =============================================================================
// СТОЛБЧАТАЯ ДИАГРАММА
// =============================================================================

/// Столбцы, вырастающие снизу вверх при появлении. Тап по столбцу
/// подсвечивает его и показывает точное значение над ним.
class BarsChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final double height;
  final String Function(double) valueFormatter;

  const BarsChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.valueFormatter,
    this.height = 190,
  });

  @override
  State<BarsChart> createState() => _BarsChartState();
}

class _BarsChartState extends State<BarsChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppDuration.chart)..forward();
  int _selected = -1;

  @override
  void didUpdateWidget(covariant BarsChart old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(child: Text('Нет данных за период', style: TextStyle(fontSize: 12, color: context.dim))),
      );
    }

    final maxV = widget.values.reduce(math.max);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The selected value is measured and rendered above the whole chart.
        // Its width therefore follows the amount, not the selected bar.
        // "12 345 ₽", so Flutter clipped the end of the amount.  Keep a
        const minBarSlot = 54.0;
        final needed = widget.values.length * minBarSlot;
        final width = math.max(constraints.maxWidth, needed).toDouble();
        final selectedText =
            _selected >= 0 ? widget.valueFormatter(widget.values[_selected]) : '';
        final selectedStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: widget.color,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: selectedText, style: selectedStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final tooltipWidth = math.min(width, textPainter.width + 20).toDouble();
        final slotWidth = width / widget.values.length;
        final tooltipLeft = (_selected < 0
            ? 0.0
            : (_selected * slotWidth + slotWidth / 2 - tooltipWidth / 2)
                .clamp(0.0, math.max(0.0, width - tooltipWidth)))
            .toDouble();
        final content = SizedBox(
          height: widget.height,
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 27,
                bottom: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < widget.values.length; i++)
                      Expanded(
                        child: _Bar(
                          value: widget.values[i],
                          maxValue: maxV <= 0 ? 1 : maxV,
                          label: i < widget.labels.length ? widget.labels[i] : '',
                          color: widget.color,
                          animation: _c,
                          delay: i / (widget.values.length * 1.6),
                          selected: _selected == i,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = _selected == i ? -1 : i);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (_selected >= 0)
                Positioned(
                  left: tooltipLeft,
                  top: 0,
                  width: tooltipWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      selectedText,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: selectedStyle,
                    ),
                  ),
                ),
            ],
          ),
        );

        if (needed <= constraints.maxWidth) return content;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // открываемся сразу на самых свежих месяцах
          physics: const BouncingScrollPhysics(),
          child: content,
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxValue;
  final String label;
  final Color color;
  final Animation<double> animation;
  final double delay;
  final bool selected;
  final VoidCallback onTap;

  const _Bar({
    required this.value,
    required this.maxValue,
    required this.label,
    required this.color,
    required this.animation,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Каждый столбец стартует чуть позже предыдущего — получается
          // «волна» роста слева направо.
          final raw = ((animation.value - delay) / (1 - delay)).clamp(0.0, 1.0);
          final t = Curves.easeOutCubic.transform(raw);
          final ratio = (value / maxValue).clamp(0.0, 1.0) * t;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: FractionallySizedBox(
                    heightFactor: ratio < 0.02 ? 0.02 : ratio,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: AppDuration.fast,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                          bottom: Radius.circular(3),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: selected
                              ? [AppGradient.lighten(color, 0.14), color]
                              : [color.withOpacity(0.85), color.withOpacity(0.32)],
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: color.withOpacity(0.45), blurRadius: 14, offset: const Offset(0, 4))]
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? color : context.dim,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// КОЛЬЦО ПРОГРЕССА
// =============================================================================

/// Кольцо выполнения — используется в планах покупок: сколько уже куплено
/// из запланированного.
class ProgressRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double thickness;
  final Color color;
  final Widget? child;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 54,
    this.thickness = 5,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
      duration: AppDuration.slow,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: v,
            color: color,
            thickness: thickness,
            track: context.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double thickness;
  final Color track;

  _RingPainter({required this.progress, required this.color, required this.thickness, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - thickness / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..shader = LinearGradient(
          colors: [color, AppGradient.lighten(color, 0.18)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.color != color;
}

/// Горизонтальная полоса-индикатор доли (вес бумаги в портфеле, прогресс плана).
class MiniProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;

  const MiniProgressBar({super.key, required this.value, required this.color, this.height = 5});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: context.isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value.clamp(0.0, 1.0)),
            duration: AppDuration.slow,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: LinearGradient(colors: [color.withOpacity(0.6), color]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
