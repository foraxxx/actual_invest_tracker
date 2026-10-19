import 'package:flutter/material.dart';

import '../design/format.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_forecast_service.dart';
import '../services/value_forecast_service.dart';
import 'choice_cards.dart';
import 'payout_forecast_sheet.dart';
import 'value_forecast_sheet.dart';

/// Общее окно «Прогноз»: сверху две карточки-итога — выплаты за 12 месяцев и
/// стоимость портфеля через выбранный срок, — нажатие на карточку
/// переключает подробности ниже. [initial]: 0 — выплаты, 1 — стоимость.
/// [onChanged] сообщает главной, что выбрано, чтобы она показывала то же.
Future<void> showForecastSheet(
  BuildContext context, {
  required int initial,
  required ValueChanged<int> onChanged,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _ForecastSheet(initial: initial, onChanged: onChanged),
  );
}

class _ForecastSheet extends StatefulWidget {
  final int initial;
  final ValueChanged<int> onChanged;

  const _ForecastSheet({required this.initial, required this.onChanged});

  @override
  State<_ForecastSheet> createState() => _ForecastSheetState();
}

class _ForecastSheetState extends State<_ForecastSheet> {
  late int _tab = widget.initial;
  int _years = ValueForecastService.defaultHorizon;

  @override
  void initState() {
    super.initState();
    // Карточка стоимости пересчитывается, когда приедет история индекса или
    // график купонов.
    ValueForecastService.version.addListener(_refresh);
    PayoutForecastService.version.addListener(_refresh);
    ValueForecastService.loadMarketHistory();
  }

  @override
  void dispose() {
    ValueForecastService.version.removeListener(_refresh);
    PayoutForecastService.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _select(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    widget.onChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    final payouts = payoutForecastTotal();
    final value = ValueForecastService.realistic(_years).result.breakdown.end;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'Прогноз',
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 4),
            ChoiceCards(
              selected: _tab,
              onSelect: _select,
              items: [
                ChoiceCard(
                  label: 'Выплаты',
                  value: '~${Fmt.money(payouts)}',
                  sub: 'за 12 месяцев',
                  color: AppColors.violet,
                  money: true,
                ),
                ChoiceCard(
                  label: 'Стоимость',
                  value: '~${Fmt.money(value)}',
                  sub: 'через ${yearsLabel(_years)} · средний сценарий',
                  color: AppColors.info,
                  money: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _tab == 0 ? payoutForecastSubtitle : valueForecastSubtitle,
              style: TextStyle(fontSize: 12.5, color: context.dim),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
              child: _tab == 0
                  ? const PayoutForecastBody(key: ValueKey('payouts'))
                  : ValueForecastBody(
                      key: const ValueKey('value'),
                      years: _years,
                      onYears: (v) => setState(() => _years = v),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
