import 'package:flutter/material.dart';
import '../data/securities.dart';
import '../data/security_info.dart';
import '../design/tokens.dart';
import '../services/favorites_service.dart';
import 'ticker_avatar.dart';

/// Поле выбора бумаги с автокомплитом по встроенному справочнику: можно
/// выбрать готовую бумагу или ввести свою (для того, чего нет в справочнике).
/// В редизайне выпадающий список получил карточное оформление, аватарки и
/// звёздочку избранного прямо в строке.
class SecurityPickerField extends StatelessWidget {
  final void Function(SecurityInfo) onSelected;
  final String hintText;

  const SecurityPickerField({
    super.key,
    required this.onSelected,
    this.hintText = 'Найти бумагу по тикеру или названию',
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
        if (textEditingValue.text.isEmpty) {
          // Пустой запрос — показываем избранное: чаще всего покупают именно
          // то, что уже отслеживаешь.
          final favTickers = FavoritesService.all;
          if (favTickers.isEmpty) return SecuritiesDatabase.search('');
          final favs = favTickers
              .map((t) => SecuritiesDatabase.byTicker(t))
              .whereType<SecurityInfo>()
              .toList();
          return favs;
        }
        return SecuritiesDatabase.search(textEditingValue.text);
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
                      title: Text(s.ticker, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      subtitle: Text(
                        '${s.name} · ${s.sector.isEmpty ? "Без сектора" : s.sector}',
                        maxLines: 1,
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
