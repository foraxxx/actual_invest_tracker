import 'package:flutter/material.dart';

import '../data/securities.dart';
import '../data/security_info.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/favorites_service.dart';
import '../services/moex_sync_service.dart';
import '../services/storage_service.dart';
import 'ticker_avatar.dart';

/// Поле «Бумага»: нажатие открывает выбор бумаги снизу — поиск и кнопки
/// «Все · Избранное · Акции · Облигации · Фонды».
class SecurityPickerField extends StatelessWidget {
  final void Function(SecurityInfo) onSelected;
  final String hintText;

  /// Какие бумаги показывать. Не задан — все.
  final bool Function(SecurityInfo)? filter;

  /// Только бумаги, которые есть в портфеле, — для продажи.
  final bool holdingsOnly;

  const SecurityPickerField({
    super.key,
    required this.onSelected,
    this.hintText = 'Выбрать бумагу',
    this.filter,
    this.holdingsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
      borderRadius: AppRadius.all(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final s = await showSecurityPicker(context, filter: filter, holdingsOnly: holdingsOnly);
          if (s != null) onSelected(s);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(AppRadius.sm),
            border: Border.all(color: context.hairline, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: context.dim),
              const SizedBox(width: 10),
              Expanded(child: Text(hintText, style: TextStyle(fontSize: 14.5, color: context.dim))),
              Icon(Icons.expand_more_rounded, color: context.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Лист выбора бумаги. Возвращает выбранную или null.
Future<SecurityInfo?> showSecurityPicker(BuildContext context,
    {bool Function(SecurityInfo)? filter, bool holdingsOnly = false}) {
  return showAppSheet<SecurityInfo>(
    context: context,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.86,
      child: _PickerSheet(filter: filter, holdingsOnly: holdingsOnly),
    ),
  );
}

enum _Tab { all, favorites, stocks, bonds, funds }

class _PickerSheet extends StatefulWidget {
  final bool Function(SecurityInfo)? filter;
  final bool holdingsOnly;
  const _PickerSheet({this.filter, this.holdingsOnly = false});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _ctrl = TextEditingController();
  _Tab _tab = _Tab.all;
  String _q = '';

  /// Все бумаги по обороту за день — сортируются один раз при открытии.
  late final List<SecurityInfo> _byTurnover;
  late final List<SecurityInfo> _favorites;
  late final List<SecurityInfo> _recent;
  late final Map<String, double> _prices;

  /// Сколько штук каждой бумаги в портфеле — для режима продажи.
  Map<String, double> _qty = const {};

  @override
  void initState() {
    super.initState();
    final fits = widget.filter;
    final snapshot = MoexSyncService.marketSnapshot.value;
    _prices = {for (final e in snapshot.entries) e.key: e.value.price};
    final turnover = {for (final e in snapshot.entries) e.key: e.value.turnover};
    final List<SecurityInfo> pool;
    if (widget.holdingsOnly) {
      // Продать можно только то, что есть: список — бумаги портфеля.
      final names = {for (final p in StorageService.purchases) p.ticker.toUpperCase(): p};
      final holdings = AnalyticsService.currentHoldings();
      _qty = {for (final e in holdings.entries) if (e.value.qty > 1e-9) e.key.toUpperCase(): e.value.qty};
      pool = [
        for (final t in _qty.keys)
          SecuritiesDatabase.byTicker(t) ??
              SecurityInfo(
                ticker: names[t]?.ticker ?? t,
                name: names[t]?.name ?? t,
                type: names[t]?.type ?? AssetType.stock,
                sector: names[t]?.sector ?? '',
              ),
      ];
    } else {
      pool = fits == null ? SecuritiesDatabase.all.toList() : SecuritiesDatabase.all.where(fits).toList();
    }
    pool.sort((a, b) =>
        (turnover[b.ticker.toUpperCase()] ?? 0).compareTo(turnover[a.ticker.toUpperCase()] ?? 0));
    _byTurnover = pool;

    final index = {for (final s in pool) s.ticker.toUpperCase(): s};
    _favorites = [
      for (final t in FavoritesService.all)
        if (index[t.toUpperCase()] != null) index[t.toUpperCase()]!,
    ];
    final trades = StorageService.purchases.toList()..sort((a, b) => b.date.compareTo(a.date));
    final seen = <String>{for (final s in _favorites) s.ticker.toUpperCase()};
    _recent = [];
    for (final p in trades) {
      final key = p.ticker.toUpperCase();
      if (!seen.add(key)) continue;
      final s = index[key] ?? SecurityInfo(ticker: p.ticker, name: p.name, type: p.type, sector: p.sector ?? '');
      if (fits != null && !fits(s)) continue;
      _recent.add(s);
      if (_recent.length >= 5) break;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _typeOk(SecurityInfo s) => switch (_tab) {
        _Tab.stocks => s.type == AssetType.stock,
        _Tab.bonds => s.type == AssetType.bond,
        _Tab.funds => s.type == AssetType.etf,
        _ => true,
      };

  List<SecurityInfo> _items() {
    if (widget.holdingsOnly) {
      final q = _q.trim().toLowerCase();
      return _byTurnover
          .where((s) => _typeOk(s) && (q.isEmpty || s.ticker.toLowerCase().contains(q) || s.name.toLowerCase().contains(q)))
          .toList();
    }
    if (_q.trim().isNotEmpty) {
      final fits = widget.filter;
      return SecuritiesDatabase.search(
        _q.trim(),
        where: (s) => (fits == null || fits(s)) && _typeOk(s) &&
            (_tab != _Tab.favorites || FavoritesService.isFavorite(s.ticker)),
      );
    }
    return switch (_tab) {
      _Tab.favorites => _favorites,
      _Tab.all => _byTurnover,
      _ => _byTurnover.where(_typeOk).toList(),
    };
  }

  Widget _chip(String label, _Tab tab) {
    final on = _tab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on
            ? (context.isDark ? Colors.white : const Color(0xFF111318))
            : (context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _tab = tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? (context.isDark ? const Color(0xFF111318) : Colors.white) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(SecurityInfo s) {
    final price = _prices[s.ticker.toUpperCase()];
    return InkWell(
      onTap: () => Navigator.pop(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            TickerAvatar(ticker: s.ticker, size: 34, glow: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text('${s.ticker} · ${Fmt.assetType(s.type).toLowerCase()}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.dim)),
                ],
              ),
            ),
            if (widget.holdingsOnly) ...[
              const SizedBox(width: 8),
              Text('${Fmt.qty(_qty[s.ticker.toUpperCase()] ?? 0)} шт', style: const TextStyle(fontSize: 13.5)),
            ] else if (price != null && price > 0) ...[
              const SizedBox(width: 8),
              Text(Fmt.price(price, type: s.type), style: const TextStyle(fontSize: 13.5)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final showRecent = !widget.holdingsOnly && _tab == _Tab.favorites && _q.trim().isEmpty && _recent.isNotEmpty;
    final types = {for (final s in _byTurnover) s.type};
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: widget.holdingsOnly ? 'Что продаёте' : 'Выбор бумаги'),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            onChanged: (v) => setState(() => _q = v),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Тикер или название',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Все', _Tab.all),
                if (!widget.holdingsOnly) _chip('Избранное', _Tab.favorites),
                if (!widget.holdingsOnly || types.contains(AssetType.stock)) _chip('Акции', _Tab.stocks),
                if (!widget.holdingsOnly || types.contains(AssetType.bond)) _chip('Облигации', _Tab.bonds),
                if (!widget.holdingsOnly || types.contains(AssetType.etf)) _chip('Фонды', _Tab.funds),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            // Список строится по мере прокрутки — тысячи облигаций не
            // рисуются разом.
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: items.length + (showRecent ? _recent.length + 1 : 0) + (items.isEmpty && !showRecent ? 1 : 0),
              itemBuilder: (context, i) {
                if (items.isEmpty && !showRecent) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Text(
                      widget.holdingsOnly && _byTurnover.isEmpty
                          ? 'В портфеле пока нет бумаг'
                          : _tab == _Tab.favorites
                              ? 'В избранном пока ничего нет'
                              : 'Ничего не найдено',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.dim),
                    ),
                  );
                }
                if (i < items.length) return _row(items[i]);
                final j = i - items.length;
                if (j == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 2),
                    child: Text('Недавние', style: TextStyle(fontSize: 12, color: context.dim)),
                  );
                }
                return _row(_recent[j - 1]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
