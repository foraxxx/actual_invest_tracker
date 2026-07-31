import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

/// Текстовое поле формы: при фокусе подсвечивается акцентной рамкой и мягким
/// свечением, так что всегда понятно, куда сейчас пишешь.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final String? suffixText;
  final bool number;
  final bool upperCase;
  final bool autofocus;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.suffixText,
    this.number = false,
    this.upperCase = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return AnimatedContainer(
      duration: AppDuration.fast,
      decoration: BoxDecoration(
        borderRadius: AppRadius.all(AppRadius.sm),
        boxShadow: _focused
            ? [BoxShadow(color: accent.withOpacity(0.22), blurRadius: 18, spreadRadius: -4)]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        textCapitalization: widget.upperCase ? TextCapitalization.characters : TextCapitalization.sentences,
        keyboardType: widget.number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 19),
          suffixText: widget.suffixText,
          suffixStyle: TextStyle(color: context.dim, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}

/// Выпадающий список в оформлении приложения.
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final IconData? icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Widget? hint;

  const AppDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.icon,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: hint,
      borderRadius: AppRadius.all(AppRadius.sm),
      dropdownColor: context.isDark ? AppColors.darkSurfaceHigh : Colors.white,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      icon: Icon(Icons.expand_more_rounded, color: context.dim),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 19),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Кнопка выбора даты — выглядит как поле формы, но открывает календарь.
class AppDateField extends StatelessWidget {
  final DateTime? value;
  final String label;
  final String emptyLabel;
  final ValueChanged<DateTime> onPicked;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDateField({
    super.key,
    required this.value,
    required this.label,
    required this.onPicked,
    this.emptyLabel = 'Не выбрана',
    this.firstDate,
    this.lastDate,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.sm),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(2010),
          lastDate: lastDate ?? DateTime(now.year + 10),
        );
        if (picked != null) onPicked(picked);
      },
      // Дата — текст фиксированной длины (10 символов), и в половине ширины
      // экрана она переставала помещаться рядом с иконкой и стрелкой: строка
      // переносилась на два ряда. В узком поле убираем стрелку, поджимаем
      // отступы, а саму дату при нехватке места ужимаем, а не переносим.
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.hasBoundedWidth && box.maxWidth < 210;
          return Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14, vertical: 13),
            decoration: BoxDecoration(
              color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
              borderRadius: AppRadius.all(AppRadius.sm),
              border: Border.all(color: context.hairline, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: compact ? 17 : 19, color: context.dim),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: context.dim, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value == null ? emptyLabel : _fmt(value!),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) Icon(Icons.chevron_right_rounded, size: 20, color: context.dim),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Переключатель на 2–4 варианта с плавно едущим индикатором — заменяет
/// SegmentedButton там, где важен «дорогой» вид (покупка/продажа и т.п.).
class SegmentedToggle<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;
  final Color Function(T)? colorOf;
  final ValueChanged<T> onChanged;
  final double height;

  const SegmentedToggle({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.colorOf,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(selected);
    final activeColor = colorOf?.call(selected) ?? context.accent;

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
        borderRadius: AppRadius.all(AppRadius.sm),
        border: Border.all(color: context.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppDuration.normal,
                curve: Curves.easeOutCubic,
                left: index < 0 ? 0 : slot * index,
                top: 0,
                bottom: 0,
                width: slot,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    gradient: LinearGradient(
                      colors: [activeColor, AppGradient.lighten(activeColor, 0.1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: activeColor.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(v);
                        },
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (iconOf?.call(v) != null) ...[
                                Icon(
                                  iconOf!.call(v),
                                  size: 16,
                                  color: v == selected ? Colors.white : context.dim,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  labelOf(v),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: v == selected ? FontWeight.w800 : FontWeight.w600,
                                    color: v == selected ? Colors.white : context.dim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Строка поиска со сбросом одним нажатием.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Поиск',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

/// Чекбокс-строка в оформлении приложения (вместо CheckboxListTile, который
/// в тёмной теме выглядит инородно).
class AppCheckRow extends StatelessWidget {
  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool> onChanged;

  const AppCheckRow({
    super.key,
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: AppDuration.fast,
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: value ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: value ? accent : context.dim.withOpacity(0.6), width: 1.6),
              ),
              child: value ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!, style: TextStyle(fontSize: 11.3, height: 1.35, color: context.dim)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
