import 'package:flutter/material.dart';

import '../design/fields.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/payout_forecast_service.dart';
import '../services/value_forecast_service.dart';
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Прогноз', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Как считается',
                  icon: Icon(Icons.info_outline_rounded, color: context.dim),
                  onPressed: () => _showInfo(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedToggle<int>(
              values: const [0, 1],
              selected: _tab,
              labelOf: (v) => v == 0 ? 'Выплаты' : 'Стоимость',
              onChanged: _select,
              height: 40,
            ),
            const SizedBox(height: 14),
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

  void _showInfo(BuildContext context) {
    if (_tab == 0) {
      showInfoSheet(context, title: 'Как считается прогноз выплат', parts: payoutForecastInfo());
    } else {
      showInfoSheet(
        context,
        title: 'Как считается прогноз стоимости',
        parts: valueForecastInfo(),
        footer: 'Это расчёт по допущениям, а не обещание: рынок может пойти иначе.',
      );
    }
  }
}
