import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/tokens.dart';
import '../services/portfolio_service.dart';
import '../services/storage_service.dart';
import '../services/tax_service.dart';

/// Доход за год против порога 2,4 млн ₽, после которого ставка — 15%.
/// Считается по всем портфелям. Предупреждение — когда пройдено 80% порога.
class TaxThresholdBar extends StatefulWidget {
  const TaxThresholdBar({super.key});

  @override
  State<TaxThresholdBar> createState() => _TaxThresholdBarState();
}

class _TaxThresholdBarState extends State<TaxThresholdBar> {
  late Future<double> _income;

  @override
  void initState() {
    super.initState();
    _load();
    StorageService.dataVersion.addListener(_reload);
    PortfolioService.version.addListener(_reload);
  }

  @override
  void dispose() {
    StorageService.dataVersion.removeListener(_reload);
    PortfolioService.version.removeListener(_reload);
    super.dispose();
  }

  void _load() => _income = TaxService.yearIncomeAllPortfolios(DateTime.now().year);

  void _reload() {
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _income,
      builder: (context, snap) {
        final income = snap.data ?? 0;
        const limit = TaxService.progressiveThreshold;
        final share = (income / limit).clamp(0.0, 1.0).toDouble();
        final near = income >= limit * 0.8;
        final over = income >= limit;
        final color = over ? AppColors.negative : (near ? AppColors.gold : AppColors.positive);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Доход за ${DateTime.now().year} для налога',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                ),
                Text(snap.hasData ? Fmt.compact(income) : '…',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 7,
                backgroundColor: context.hairline,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '2,4 млн — дальше налог 15%. Дивиденды, купоны и прибыль от продаж по всем портфелям.',
              style: TextStyle(fontSize: 11, height: 1.35, color: context.dim),
            ),
            if (near) ...[
              const SizedBox(height: 8),
              TaxNote(
                color: color,
                text: over
                    ? 'Доход за год больше 2,4 млн — с превышения налог 15%. Поставьте ставку 15%, чтобы прогнозы были точнее.'
                    : 'До повышенной ставки осталось ${Fmt.money(limit - income)}. С дохода сверх 2,4 млн налог будет 15%.',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Цветная плашка-пояснение.
class TaxNote extends StatelessWidget {
  final String text;
  final Color color;
  const TaxNote({super.key, required this.text, this.color = AppColors.violet});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
      );
}
