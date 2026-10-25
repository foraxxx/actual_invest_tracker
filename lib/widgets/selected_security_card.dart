import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/tokens.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import 'ticker_avatar.dart';

/// Выбранная бумага в форме сделки — маленькая карточка вместо полей
/// «Тикер» и «Название»: логотип, название, тикер, тип и лот, сколько бумаг
/// уже есть. Текущая цена здесь не пишется — она подставляется в поле цены.
class SelectedSecurityCard extends StatelessWidget {
  final String ticker;
  final String name;
  final AssetType type;
  final int lotSize;

  /// Для продажи рядом с количеством пишется средняя цена.
  final bool isSell;

  /// «Сменить» — вернуться к поиску. null — бумагу поменять нельзя.
  final VoidCallback? onChange;

  const SelectedSecurityCard({
    super.key,
    required this.ticker,
    required this.name,
    required this.type,
    required this.lotSize,
    this.isSell = false,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final holding = AnalyticsService.currentHoldings()[ticker.toUpperCase()];
    final has = holding != null && holding.qty > 0;
    final String own;
    if (has) {
      own = isSell
          ? 'у вас ${Fmt.qty(holding.qty)} шт по ${Fmt.price(holding.avgCost, type: type)}'
          : 'у вас ${Fmt.qty(holding.qty)} шт';
    } else {
      own = isSell ? 'этой бумаги нет на счету' : 'пока нет на счету';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
        borderRadius: AppRadius.all(AppRadius.md),
      ),
      child: Row(
        children: [
          TickerAvatar(ticker: ticker, size: 40, glow: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isEmpty ? ticker.toUpperCase() : name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  '${ticker.toUpperCase()} · ${Fmt.assetType(type).toLowerCase()} · лот $lotSize',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.dim),
                ),
                Text(
                  own,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSell && !has ? AppColors.negative : context.dim,
                  ),
                ),
              ],
            ),
          ),
          if (onChange != null)
            TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: context.dim,
              ),
              child: const Text('Сменить'),
            ),
        ],
      ),
    );
  }
}

/// Строка «Сумма сделки» под полями.
class TradeSumLine extends StatelessWidget {
  final double sum;
  final double quantity;
  final String currency;
  final bool isSell;

  const TradeSumLine({
    super.key,
    required this.sum,
    required this.quantity,
    required this.currency,
    required this.isSell,
  });

  @override
  Widget build(BuildContext context) {
    final cur = currency == 'RUB' ? '₽' : currency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              '${isSell ? 'К зачислению' : 'Сумма сделки'} · ${Fmt.qty(quantity)} шт',
              style: TextStyle(fontSize: 13, color: context.dim),
            ),
          ),
          Text(
            sum > 0 ? '${Fmt.group(sum, decimals: sum < 1000 ? 2 : 0)} $cur' : '—',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
