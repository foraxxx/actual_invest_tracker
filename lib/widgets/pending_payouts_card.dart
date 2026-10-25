import 'package:flutter/material.dart';

import '../data/securities.dart';
import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../models/purchase.dart';
import '../services/analytics_service.dart';
import '../services/appearance_service.dart';
import '../services/memo.dart';
import '../services/storage_service.dart';
import 'expected_payout_tile.dart';
import 'income_sheet.dart';
import 'ticker_avatar.dart';

/// Выплата, дата которой прошла, а запись о ней ещё не сделана.
class PendingPayout {
  final String ticker;
  final String name;
  final ExpectedPayout payout;

  const PendingPayout(this.ticker, this.name, this.payout);

  DateTime get paidDate => payout.isBond ? payout.date : payout.date.add(const Duration(days: 14));
  double get net => payout.net(defaultTaxRate(payout.isBond));

  /// Ключ для «скрыть»: бумага и дата выплаты.
  String get key => '${ticker.toUpperCase()}@${payout.date.toIso8601String().substring(0, 10)}';
}

const _dismissedKey = 'payoutsDismissed';

Set<String> _dismissed() =>
    (AppearanceService.ui(_dismissedKey) ?? '').split(',').where((s) => s.isNotEmpty).toSet();

/// Скрыть плашку для этих выплат. Новая выплата покажется снова.
Future<void> dismissPendingPayouts(List<PendingPayout> list) async {
  final keys = {..._dismissed(), for (final p in list) p.key};
  await AppearanceService.setUi(_dismissedKey, keys.join(','));
  Memo.clear();
}

/// Все такие выплаты по бумагам портфеля.
List<PendingPayout> pendingPayouts() => Memo.get('pendingPayouts', () {
      final types = <String, AssetType>{};
      final names = <String, String>{};
      for (final p in StorageService.purchases) {
        types[p.ticker.toUpperCase()] = p.type;
        names[p.ticker.toUpperCase()] = p.name;
      }
      final result = <PendingPayout>[];
      final hidden = _dismissed();
      for (final t in AnalyticsService.allOwnedTickers()) {
        final upper = t.toUpperCase();
        final isBond = types[upper] == AssetType.bond;
        final e = isBond ? ExpectedPayoutTile.forBond(t) : ExpectedPayoutTile.forStock(t);
        if (e == null || !e.$2 || e.$1.units <= 0) continue;
        final name = SecuritiesDatabase.byTicker(t)?.name ?? names[upper] ?? t;
        final item = PendingPayout(t, name, e.$1);
        if (hidden.contains(item.key)) continue;
        result.add(item);
      }
      result.sort((a, b) => b.payout.date.compareTo(a.payout.date));
      return result;
    });

/// «Пришли выплаты?» на главной: дата выплаты прошла, а записи нет.
/// «Все пришли» записывает ожидаемые суммы разом, нажатие по строке
/// открывает форму с подставленной суммой — её можно поправить.
class PendingPayoutsCard extends StatelessWidget {
  final VoidCallback onChanged;
  const PendingPayoutsCard({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final list = pendingPayouts();
    if (list.isEmpty) return const SizedBox.shrink();
    final many = list.length > 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: AppRadius.all(AppRadius.md),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Пришли выплаты?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('${list.length}', style: TextStyle(fontSize: 12.5, color: context.dim)),
              const SizedBox(width: 4),
              // Крестик прячет эти выплаты; записать их можно и в карточке бумаги.
              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Скрыть',
                  icon: Icon(Icons.close_rounded, size: 18, color: context.dim),
                  onPressed: () async {
                    await dismissPendingPayouts(list);
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          for (final p in list)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await showAddIncomeSheet(
                  context,
                  ticker: p.ticker,
                  name: p.name,
                  isBond: p.payout.isBond,
                  initialDate: p.paidDate,
                  initialAmount: (p.net * 100).round() / 100,
                  title: 'Выплата пришла',
                );
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    TickerAvatar(ticker: p.ticker, size: 30, glow: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            '${p.payout.isBond ? 'купон' : 'отсечка'} ${Fmt.dayShort(p.payout.date)} · ${Fmt.qty(p.payout.units)} шт',
                            style: TextStyle(fontSize: 12, color: context.dim),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    HiddenAmount.forText(
                      '≈ ${Fmt.money(p.net)}',
                      fontSize: 14,
                      child: Text('≈ ${Fmt.money(p.net)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: many ? 'Все пришли' : 'Пришла',
                  onPressed: () async {
                    for (final p in list) {
                      await confirmExpectedPayout(
                        ticker: p.ticker,
                        name: p.name,
                        expected: p.payout,
                        paidDate: p.paidDate,
                      );
                    }
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GradientButton(
                  label: 'Другая сумма',
                  secondary: true,
                  onPressed: () async {
                    // Первая из списка — остальные останутся на главной.
                    final p = list.first;
                    await showAddIncomeSheet(
                      context,
                      ticker: p.ticker,
                      name: p.name,
                      isBond: p.payout.isBond,
                      initialDate: p.paidDate,
                      initialAmount: (p.net * 100).round() / 100,
                      title: 'Выплата пришла',
                    );
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          if (many)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Нажмите на выплату, чтобы записать её с другой суммой',
                style: TextStyle(fontSize: 11.5, color: context.dim),
              ),
            ),
        ],
      ),
    );
  }
}
