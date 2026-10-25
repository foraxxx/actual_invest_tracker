import 'package:flutter/material.dart';

import '../data/securities.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/plan.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/trade_edit_sheet.dart';
import 'ticker_detail_screen.dart';

/// Поиск по всему приложению: мои бумаги, сделки, планы и бумаги биржи.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _nameOf(String ticker) {
    final ref = SecuritiesDatabase.byTicker(ticker)?.name.trim();
    if (ref != null && ref.isNotEmpty) return ref;
    for (final p in StorageService.purchases) {
      if (p.ticker.toUpperCase() == ticker.toUpperCase() && p.name.trim().isNotEmpty) return p.name;
    }
    return ticker;
  }

  bool _hit(String ticker, String name) {
    final q = _q.toLowerCase();
    return ticker.toLowerCase().contains(q) || name.toLowerCase().contains(q);
  }

  void _openTicker(String ticker) =>
      Navigator.push(context, AppPageRoute(builder: (_) => TickerDetailScreen(ticker: ticker)));

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text(title, style: TextStyle(fontSize: 12.5, color: context.dim, fontWeight: FontWeight.w600)),
      );

  Widget _row(String ticker, String title, String sub, {String? right, required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              TickerAvatar(ticker: ticker, size: 34, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.dim)),
                  ],
                ),
              ),
              if (right != null) ...[
                const SizedBox(width: 8),
                Text(right, style: TextStyle(fontSize: 12.5, color: context.dim)),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (_q.trim().isNotEmpty) {
      final holdings = AnalyticsService.currentHoldings();
      final mine = [
        for (final e in holdings.entries)
          if (e.value.qty > 0 && _hit(e.key, _nameOf(e.key))) e,
      ];
      final trades = (StorageService.purchases.where((p) => _hit(p.ticker, p.name)).toList()
            ..sort((a, b) => b.date.compareTo(a.date)))
          .take(20)
          .toList();
      final plans = StorageService.plans.where((p) => _hit(p.ticker, p.name)).toList()
        ..sort((a, b) => (a.targetDate ?? DateTime(9999)).compareTo(b.targetDate ?? DateTime(9999)));
      final own = holdings.keys.map((t) => t.toUpperCase()).toSet();
      final market = SecuritiesDatabase.search(_q.trim())
          .where((s) => !own.contains(s.ticker.toUpperCase()))
          .take(15)
          .toList();

      if (mine.isNotEmpty) {
        children.add(_section('Мои бумаги'));
        for (final e in mine) {
          children.add(_row(
            e.key,
            _nameOf(e.key),
            '${Fmt.qty(e.value.qty)} шт · ${Fmt.money(e.value.valueRub)}',
            onTap: () => _openTicker(e.key),
          ));
        }
      }
      if (trades.isNotEmpty) {
        children.add(_section('Сделки'));
        for (final Purchase p in trades) {
          children.add(_row(
            p.ticker,
            '${p.name} · ${p.isSell ? 'продажа' : 'покупка'} ${Fmt.qty(p.quantity)} шт',
            '${Fmt.date(p.date)} · ${p.isSell ? '+' : '−'}${Fmt.money(p.settlementAmount)}',
            onTap: () async {
              await showEditTradeSheet(context, p, withTickerLink: true);
              if (mounted) setState(() {});
            },
          ));
        }
      }
      if (plans.isNotEmpty) {
        children.add(_section('Планы'));
        for (final Plan p in plans) {
          final d = p.targetDate;
          children.add(_row(
            p.ticker,
            p.name,
            '${d == null ? 'без срока' : 'до ${Fmt.dayShort(d)}'} · ${Fmt.qty(p.purchasedQuantity)} из ${Fmt.qty(p.targetQuantity)} шт',
            right: p.estimatedTotal == null ? null : '≈ ${Fmt.money(p.estimatedTotal!)}',
            onTap: () => _openTicker(p.ticker),
          ));
        }
      }
      if (market.isNotEmpty) {
        children.add(_section('На бирже'));
        for (final s in market) {
          children.add(_row(s.ticker, s.name, '${s.ticker} · ${Fmt.assetType(s.type).toLowerCase()}',
              onTap: () => _openTicker(s.ticker)));
        }
      }
      if (children.isEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(icon: Icons.search_off_rounded, title: 'Ничего не найдено'),
        ));
      }
    } else {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(
          'Бумаги, сделки и планы — по тикеру или названию',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.dim),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Поиск',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _ctrl.clear();
                      _q = '';
                    }),
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      ),
    );
  }
}
