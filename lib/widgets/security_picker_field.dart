import 'package:flutter/material.dart';
import '../data/securities.dart';
import '../data/security_info.dart';
import '../design/tokens.dart';
import '../services/favorites_service.dart';
import '../services/storage_service.dart';
import 'ticker_avatar.dart';

/// Поле выбора бумаги с автокомплитом по встроенному справочнику: можно
/// выбрать готовую бумагу или ввести свою (для того, чего нет в справочнике).
/// В редизайне выпадающий список получил карточное оформление, аватарки и
/// звёздочку избранного прямо в строке.
class SecurityPickerField extends StatelessWidget {
  final void Function(SecurityInfo) onSelected;
  final String hintText;

  /// Какие бумаги показывать. Не задан — все.
  final bool Function(SecurityInfo)? filter;

  const SecurityPickerField({
    super.key,
    required this.onSelected,
    this.hintText = 'Найти бумагу по тикеру или названию',
    this.filter,
  });

  @override
  Widget build(BuildContext context) {
    // Ширину поля надо знать заранее: выпадающий список Autocomplete получает
    // ограничения по всему экрану, а не по полю, и без явной ширины уезжает
    // вправо за край.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double fieldWidth) {
    return Autocomplete<SecurityInfo>(
      displayStringForOption: (s) => '${s.ticker} — ${s.name}',
      optionsBuilder: (textEditingValue) {
        final fits = filter;
        if (textEditingValue.text.isEmpty) {
          // Пустой запрос — несколько бумаг из последних сделок. Избранное
          // здесь больше не показывается: оно мешало искать нужную бумагу.
          final trades = StorageService.purchases.toList()..sort((a, b) => b.date.compareTo(a.date));
          final seen = <String>{};
          final recent = <SecurityInfo>[];
          for (final t in trades) {
            if (!seen.add(t.ticker.toUpperCase())) continue;
            final info = SecuritiesDatabase.byTicker(t.ticker) ??
                SecurityInfo(ticker: t.ticker, name: t.name, type: t.type, sector: t.sector ?? '');
            if (fits != null && !fits(info)) continue;
            recent.add(info);
            if (recent.length >= 5) break;
          }
          return recent;
        }
        return SecuritiesDatabase.search(textEditingValue.text, where: fits);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: isDark ? AppColors.darkSurfaceHigh : Colors.white,
              elevation: 12,
              shadowColor: Colors.black.withOpacity(0.4),
              borderRadius: AppRadius.all(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 300, maxWidth: fieldWidth),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: context.hairline, indent: 60),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return ListTile(
                      dense: true,
                      leading: TickerAvatar(ticker: s.ticker, size: 34, glow: false),
                      title: Text(s.ticker, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                        '${s.name} · ${s.sector.isEmpty ? "Без сектора" : s.sector}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: context.dim),
                      ),
                      trailing: StatefulBuilder(
                        builder: (context, setInnerState) => IconButton(
                          icon: Icon(
                            FavoritesService.isFavorite(s.ticker) ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 20,
                            color: FavoritesService.isFavorite(s.ticker) ? AppColors.gold : context.dim,
                          ),
                          onPressed: () async {
                            await FavoritesService.toggle(s.ticker);
                            setInnerState(() {});
                          },
                        ),
                      ),
                      onTap: () => onSelected(s),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
