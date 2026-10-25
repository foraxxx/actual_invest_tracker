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

/// Количество лотов: − и + внутри поля, число можно вписать. Под полем —
/// сколько это штук.
class LotStepper extends StatelessWidget {
  final TextEditingController controller;
  final int lotSize;
  final VoidCallback onChanged;
  final bool autofocus;

  /// Больше скольких лотов ввести нельзя — для продажи: сколько есть.
  final int? maxLots;

  const LotStepper({
    super.key,
    required this.controller,
    required this.lotSize,
    required this.onChanged,
    this.autofocus = false,
    this.maxLots,
  });

  int get _lots => int.tryParse(controller.text.replaceAll(' ', '')) ?? 0;

  void _step(int d) {
    final next = (_lots + d).clamp(1, maxLots == null || maxLots! < 1 ? 100000000 : maxLots!);
    controller.text = '$next';
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final btnColor = context.isDark ? AppColors.darkSurfaceTop : Colors.white;
    final atMax = maxLots != null && _lots >= maxLots!;
    Widget btn(IconData icon, int d) {
      final enabled = !(d > 0 && atMax);
      return Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: btnColor,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: enabled ? () => _step(d) : null,
            child: SizedBox(width: 34, height: 40, child: Icon(icon, size: 18)),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text('Лотов', style: TextStyle(fontSize: 12, color: context.dim)),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.isDark ? Colors.white.withOpacity(0.04) : AppColors.lightSurfaceHigh,
            borderRadius: AppRadius.all(AppRadius.sm),
            border: Border.all(color: context.hairline, width: 1.2),
          ),
          child: Row(
            children: [
              btn(Icons.remove_rounded, -1),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) {
                    // Больше, чем есть, продать нельзя — число уменьшается.
                    if (maxLots != null && maxLots! > 0 && _lots > maxLots!) {
                      controller.text = '$maxLots';
                      controller.selection = TextSelection.collapsed(offset: controller.text.length);
                    }
                    onChanged();
                  },
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              btn(Icons.add_rounded, 1),
            ],
          ),
        ),
      ],
    );
  }
}

/// «1 100 лотов × 10 = 11 000 шт» — подпись под строкой с лотами и ценой.
class LotCaption extends StatelessWidget {
  final int lots;
  final int lotSize;

  /// Для продажи: «Все · N» — продать всё одним нажатием.
  final int? maxLots;
  final VoidCallback? onAll;

  const LotCaption({super.key, required this.lots, required this.lotSize, this.maxLots, this.onAll});

  @override
  Widget build(BuildContext context) {
    final text = lotSize > 1
        ? '${Fmt.group(lots.toDouble())} ${Fmt.plural(lots, 'лот', 'лота', 'лотов')} × $lotSize = ${Fmt.group(lots * lotSize.toDouble())} шт'
        : '${Fmt.group(lots.toDouble())} шт';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: context.dim))),
          if (maxLots != null && maxLots! > 0 && onAll != null)
            GestureDetector(
              onTap: onAll,
              child: Text(
                'Все · ${Fmt.group(maxLots!.toDouble())}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.accent),
              ),
            ),
        ],
      ),
    );
  }
}
