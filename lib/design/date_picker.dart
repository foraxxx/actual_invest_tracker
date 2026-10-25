import 'package:flutter/material.dart';

import 'surfaces.dart';
import 'tokens.dart';

const _monthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];
const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

Color _onBg(BuildContext c) => c.isDark ? Colors.white : const Color(0xFF111111);
Color _onFg(BuildContext c) => c.isDark ? const Color(0xFF111111) : Colors.white;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Выбор даты в стиле приложения: лист снизу, месяц сеткой с понедельника,
/// быстрые кнопки «Сегодня», «Вчера», «Неделю назад». Нажатие на название
/// месяца открывает выбор месяца и года.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showAppSheet<DateTime>(
    context: context,
    builder: (_) => _DatePickerSheet(
      initial: _day(initialDate),
      first: _day(firstDate),
      last: _day(lastDate),
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime first;
  final DateTime last;

  const _DatePickerSheet({required this.initial, required this.first, required this.last});

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _selected = _clamp(widget.initial);
  late DateTime _month = DateTime(_selected.year, _selected.month);
  bool _pickMonth = false;

  DateTime _clamp(DateTime d) => d.isBefore(widget.first) ? widget.first : (d.isAfter(widget.last) ? widget.last : d);
  bool _allowed(DateTime d) => !d.isBefore(widget.first) && !d.isAfter(widget.last);

  bool get _canPrev => DateTime(_month.year, _month.month).isAfter(DateTime(widget.first.year, widget.first.month));
  bool get _canNext => DateTime(_month.year, _month.month).isBefore(DateTime(widget.last.year, widget.last.month));

  void _go(DateTime d) {
    setState(() {
      _selected = d;
      _month = DateTime(d.year, d.month);
      _pickMonth = false;
    });
  }

  Widget _chip(String label, DateTime d) {
    final on = _selected == d;
    final enabled = _allowed(d);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? _onBg(context) : (context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => _go(d) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? _onFg(context) : (enabled ? null : context.dim),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton(
          onPressed: _pickMonth
              ? (_month.year > widget.first.year ? () => setState(() => _month = DateTime(_month.year - 1, _month.month)) : null)
              : (_canPrev ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _pickMonth = !_pickMonth),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(
                TextSpan(children: [
                  if (!_pickMonth)
                    TextSpan(
                      text: '${_monthsNom[_month.month - 1]} ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  TextSpan(
                    text: '${_month.year}',
                    style: TextStyle(
                      fontWeight: _pickMonth ? FontWeight.w700 : FontWeight.w500,
                      color: _pickMonth ? null : context.dim,
                    ),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      _pickMonth ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: context.dim,
                    ),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _pickMonth
              ? (_month.year < widget.last.year ? () => setState(() => _month = DateTime(_month.year + 1, _month.month)) : null)
              : (_canNext ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _monthsGrid() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var m = 1; m <= 12; m++)
          Builder(builder: (_) {
            final first = DateTime(_month.year, m);
            final enabled = !DateTime(_month.year, m + 1, 0).isBefore(widget.first) && !first.isAfter(widget.last);
            final on = m == _month.month;
            return Material(
              color: on ? _onBg(context) : (context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: enabled ? () => setState(() {
                      _month = first;
                      _pickMonth = false;
                    }) : null,
                child: Center(
                  child: Text(
                    _monthsNom[m - 1],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? _onFg(context) : (enabled ? null : context.dim.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _daysGrid() {
    final today = _day(DateTime.now());
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // 1 — понедельник
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[
      for (final w in _weekdays)
        Center(child: Text(w, style: TextStyle(fontSize: 11.5, color: context.dim))),
      for (var i = 1; i < firstWeekday; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        Builder(builder: (_) {
          final date = DateTime(_month.year, _month.month, d);
          final on = date == _selected;
          final isToday = date == today;
          final enabled = _allowed(date);
          final weekend = date.weekday >= 6;
          return Center(
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? () => setState(() => _selected = date) : null,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? _onBg(context) : null,
                  border: isToday && !on ? Border.all(color: context.dim, width: 1.4) : null,
                ),
                child: Text(
                  '$d',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on
                        ? const Color(0xFF111111)
                        : !enabled
                            ? context.dim.withOpacity(0.35)
                            : weekend
                                ? context.dim
                                : null,
                  ),
                ),
              ),
            ),
          );
        }),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.05,
      children: cells,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('Сегодня', today),
                  _chip('Вчера', today.subtract(const Duration(days: 1))),
                  _chip('Неделю назад', today.subtract(const Duration(days: 7))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: AppDuration.fast,
              alignment: Alignment.topCenter,
              child: _pickMonth ? _monthsGrid() : _daysGrid(),
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Выбрать ${_selected.day} ${_monthsGen[_selected.month - 1]}'
                  '${_selected.year == today.year ? '' : ' ${_selected.year}'}',
              onPressed: () => Navigator.pop(context, _selected),
            ),
          ],
        ),
      ),
    );
  }
}

const _monthsShort = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

Widget _pill(BuildContext context, String label, bool on, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? _onBg(context) : (context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? _onFg(context) : null,
              ),
            ),
          ),
        ),
      ),
    );

/// Выбор месяца в том же стиле: 12 месяцев сеткой, год стрелками.
/// Возвращает первое число выбранного месяца.
Future<DateTime?> showAppMonthPicker({required BuildContext context, required DateTime initial}) {
  return showAppSheet<DateTime>(context: context, builder: (_) => _MonthSheet(initial: initial));
}

class _MonthSheet extends StatefulWidget {
  final DateTime initial;
  const _MonthSheet({required this.initial});

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late int _year = widget.initial.year;
  late DateTime _selected = DateTime(widget.initial.year, widget.initial.month);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    void pick(DateTime m) => setState(() {
          _selected = m;
          _year = m.year;
        });
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _pill(context, 'Этот месяц', _selected == thisMonth, () => pick(thisMonth)),
                _pill(context, 'Следующий', _selected == nextMonth, () => pick(nextMonth)),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var m = 1; m <= 12; m++)
                  Builder(builder: (_) {
                    final on = _selected == DateTime(_year, m);
                    return Material(
                      color: on
                          ? _onBg(context)
                          : (context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selected = DateTime(_year, m)),
                        child: Center(
                          child: Text(
                            _monthsNom[m - 1],
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                              color: on ? _onFg(context) : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Выбрать ${_monthsNom[_selected.month - 1].toLowerCase()} ${_selected.year}',
              onPressed: () => Navigator.pop(context, _selected),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор периода «с — по»: первое нажатие — начало, второе — конец.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initial,
}) {
  return showAppSheet<DateTimeRange>(
    context: context,
    builder: (_) => _RangeSheet(first: _day(firstDate), last: _day(lastDate), initial: initial),
  );
}

class _RangeSheet extends StatefulWidget {
  final DateTime first;
  final DateTime last;
  final DateTimeRange? initial;
  const _RangeSheet({required this.first, required this.last, this.initial});

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late DateTime? _start = widget.initial == null ? null : _day(widget.initial!.start);
  late DateTime? _end = widget.initial == null ? null : _day(widget.initial!.end);
  late DateTime _month = DateTime((_start ?? DateTime.now()).year, (_start ?? DateTime.now()).month);

  String _fmt(DateTime? d) => d == null ? '—' : '${d.day} ${_monthsGen[d.month - 1]}${d.year == DateTime.now().year ? '' : ' ${d.year}'}';
  String _short(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  void _tap(DateTime d) {
    setState(() {
      if (_start == null || _end != null) {
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  void _preset(DateTime a, DateTime b) => setState(() {
        _start = a;
        _end = b;
        _month = DateTime(a.year, a.month);
      });

  Widget _field(String label, DateTime? d) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: context.dim)),
              const SizedBox(height: 2),
              Text(_fmt(d), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final band = context.accent.withOpacity(0.2);
    final end = _end ?? _start;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Период', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                TextButton(
                  onPressed: () => setState(() {
                    _start = null;
                    _end = null;
                  }),
                  child: const Text('Сбросить'),
                ),
              ],
            ),
            Row(children: [_field('С', _start), const SizedBox(width: 8), _field('По', _end)]),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _pill(context, 'Этот месяц', false,
                      () => _preset(DateTime(today.year, today.month), DateTime(today.year, today.month + 1, 0))),
                  _pill(context, '3 месяца', false,
                      () => _preset(DateTime(today.year, today.month), DateTime(today.year, today.month + 3, 0))),
                  _pill(context, 'Этот год', false, () => _preset(DateTime(today.year), DateTime(today.year, 12, 31))),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${_monthsNom[_month.month - 1]} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: '${_month.year}', style: TextStyle(color: context.dim)),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              mainAxisSpacing: 2,
              children: [
                for (final w in _weekdays)
                  Center(child: Text(w, style: TextStyle(fontSize: 11.5, color: context.dim))),
                for (var i = 1; i < firstWeekday; i++) const SizedBox.shrink(),
                for (var d = 1; d <= days; d++)
                  Builder(builder: (_) {
                    final date = DateTime(_month.year, _month.month, d);
                    final enabled = !date.isBefore(widget.first) && !date.isAfter(widget.last);
                    final isEdge = date == _start || date == _end;
                    final inside = _start != null && end != null && !date.isBefore(_start!) && !date.isAfter(end);
                    final weekend = date.weekday >= 6;
                    return GestureDetector(
                      onTap: enabled ? () => _tap(date) : null,
                      child: Container(
                        color: inside && _end != null && _start != _end ? band : null,
                        alignment: Alignment.center,
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isEdge ? _onBg(context) : null,
                            border: date == today && !isEdge ? Border.all(color: context.dim, width: 1.4) : null,
                          ),
                          child: Text(
                            '$d',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isEdge ? FontWeight.w700 : FontWeight.w500,
                              color: isEdge
                                  ? _onFg(context)
                                  : !enabled
                                      ? context.dim.withOpacity(0.35)
                                      : weekend
                                          ? context.dim
                                          : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: _start == null ? 'Выберите начало периода' : 'Показать · ${_short(_start!)} — ${_short(end!)}',
              onPressed: _start == null
                  ? null
                  : () => Navigator.pop(context, DateTimeRange(start: _start!, end: end!)),
            ),
          ],
        ),
      ),
    );
  }
}
