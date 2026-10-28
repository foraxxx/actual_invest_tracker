import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../design/format.dart';
import 'annual_report_service.dart';

/// Сборка годового отчёта в PDF.
///
/// Встроенные шрифты библиотеки не знают кириллицу — русский текст выходил бы
/// пустыми прямоугольниками, поэтому в приложение вшит DejaVu Sans Condensed.
class ReportPdfService {
  ReportPdfService._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansCondensed.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansCondensed-Bold.ttf'));
  }

  static const _accent = PdfColor.fromInt(0xFF18A36B);
  static const _positive = PdfColor.fromInt(0xFF18A36B);
  static const _negative = PdfColor.fromInt(0xFFD64545);
  static const _muted = PdfColor.fromInt(0xFF8A8F99);
  static const _line = PdfColor.fromInt(0xFFECEEF2);
  static const _violet = PdfColor.fromInt(0xFF7C6CFF);

  static const _monthsShort = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

  /// Собирает документ и сохраняет его в файл. Возвращает путь.
  static Future<String> save(
    AnnualReport report, {
    String? portfolioName,
    double? imoexPct,
    double? inflationPct,
    double? keyRatePct,
  }) async {
    final bytes = await build(
      report,
      portfolioName: portfolioName,
      imoexPct: imoexPct,
      inflationPct: inflationPct,
      keyRatePct: keyRatePct,
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/itogi_${report.year}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static PdfColor _pnl(double v) => v > 0 ? _positive : (v < 0 ? _negative : PdfColors.black);

  static Future<Uint8List> build(
    AnnualReport report, {
    String? portfolioName,
    double? imoexPct,
    double? inflationPct,
    double? keyRatePct,
  }) async {
    await _loadFonts();
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    final doc = pw.Document(title: 'Итоги ${report.year}');
    final result = report.totalResultRub;
    final growth = report.valueEndRub - report.valueStartRub - report.boughtRub + report.soldRub;

    final ranked = report.rows.where((r) => r.valueStartRub + r.boughtSumRub > 0).toList()
      ..sort((a, b) => b.yieldPct.compareTo(a.yieldPct));
    final topPayout = report.payoutEvents.isEmpty
        ? null
        : (report.payoutEvents.toList()..sort((a, b) => b.rub.compareTo(a.rub))).first;
    final story = [
      if (ranked.isNotEmpty && ranked.first.yieldPct > 0)
        'Лучшая бумага — ${ranked.first.name} (${Fmt.pct(ranked.first.yieldPct)}).',
      if (topPayout != null)
        'Крупнейшая выплата — ${topPayout.name}, ${Fmt.money(topPayout.rub)} в ${_monthsShort[topPayout.date.month - 1]}.',
      if (report.trades.isNotEmpty) 'Сделок за год — ${report.trades.length}.',
    ].join(' ');

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Invest Tracker · Итоги ${report.year}', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.Text('${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          ],
        ),
        build: (context) => [
          // --- Сводка ---
          pw.Text('ИТОГИ ГОДА', style: const pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 2)),
          pw.SizedBox(height: 2),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('${report.year}', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
              if (portfolioName != null) ...[
                pw.SizedBox(width: 10),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(portfolioName, style: const pw.TextStyle(fontSize: 11, color: _muted)),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Прирост портфеля', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          pw.Text(Fmt.signedMoney(result),
              style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: _pnl(result))),
          pw.Text(
            '${Fmt.pct(report.yieldPct)} · ${Fmt.money(report.valueStartRub)} → ${Fmt.money(report.valueEndRub)}',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColor.fromInt(0xFF555B66)),
          ),
          pw.SizedBox(height: 16),
          _grid([
            ('Вложено за год', Fmt.signedMoney(report.investedRub), null),
            ('Выплаты', Fmt.money(report.payoutsRub), _positive),
            ('Прибыль от продаж', Fmt.signedMoney(report.realizedRub), _pnl(report.realizedRub)),
            ('Налоги', Fmt.money(report.taxPaidRub), null),
            ('Доходность', Fmt.pct(report.yieldPct), _pnl(report.yieldPct)),
            ('Индекс Мосбиржи', imoexPct == null ? '—' : Fmt.pct(imoexPct), null),
          ]),
          if (report.valueSeries.length >= 2) ...[
            pw.SizedBox(height: 18),
            _label('Стоимость портфеля'),
            _lineChart(report.valueSeries.map((e) => e.value).toList(), _pnl(result), height: 90),
            _monthAxis(),
          ],
          if (story.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Container(height: 0.6, color: _line),
            pw.SizedBox(height: 8),
            pw.Text(story, style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF555B66), lineSpacing: 2)),
          ],

          // --- Из чего сложился год и сравнение ---
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _h('Из чего сложился год'),
                    _kv('На 1 января', Fmt.money(report.valueStartRub)),
                    _kv('Куплено бумаг', '+${Fmt.money(report.boughtRub)}'),
                    _kv('Продано бумаг', '−${Fmt.money(report.soldRub)}'),
                    _kv('Рост цен', Fmt.signedMoney(growth), color: _pnl(growth)),
                    _kv('Выплаты', '+${Fmt.money(report.payoutsRub)}', color: _positive),
                    _kv('Налоги и комиссии', '−${Fmt.money(report.taxPaidRub + report.feesRub)}', color: _negative),
                    _kv('На конец периода', Fmt.money(report.valueEndRub), bold: true, top: true),
                  ],
                ),
              ),
              pw.SizedBox(width: 28),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _h('Доходность в сравнении'),
                    _kv('Мой портфель', Fmt.pct(report.yieldPct), color: _pnl(report.yieldPct), bold: true),
                    _kv('Индекс Мосбиржи', imoexPct == null ? '—' : Fmt.pct(imoexPct)),
                    _kv('Инфляция', inflationPct == null ? '—' : Fmt.pct(inflationPct)),
                    _kv('Вклад под ключевую', keyRatePct == null ? '—' : '≈ ${Fmt.pct(keyRatePct)}'),
                    if (report.taxes != null &&
                        (report.taxes!.dividends + report.taxes!.coupons + report.taxes!.sales) > 0.5) ...[
                      pw.SizedBox(height: 10),
                      _h('Налоги за год'),
                      if (report.taxes!.dividends > 0.5) _kv('С дивидендов — удержано', Fmt.money(report.taxes!.dividends)),
                      if (report.taxes!.coupons > 0.5)
                        _kv(report.taxes!.deferred ? 'С купонов — при закрытии ИИС' : 'С купонов — брокер удержит',
                            '≈ ${Fmt.money(report.taxes!.coupons)}'),
                      if (report.taxes!.sales > 0.5)
                        _kv(report.taxes!.deferred ? 'С продаж — при закрытии ИИС' : 'С продаж',
                            '≈ ${Fmt.money(report.taxes!.sales)}'),
                      _kv('Итого', '≈ ${Fmt.money(report.taxes!.total)}', color: _negative, bold: true, top: true),
                      if (report.taxes!.saved > 0.5)
                        _kv('ИИС сэкономил', '≈ ${Fmt.money(report.taxes!.saved)}', color: _positive),
                    ],
                    pw.SizedBox(height: 10),
                    _h('Сделки'),
                    _kv('Куплено', Fmt.money(report.boughtRub)),
                    _kv('Продано', Fmt.money(report.soldRub)),
                    _kv('Сделок', '${report.trades.length}'),
                    _kv('Комиссии', Fmt.money(report.feesRub)),
                  ],
                ),
              ),
            ],
          ),

          // --- Пополнения и выплаты ---
          if (report.depositsByMonth.isNotEmpty || report.payoutsByMonth.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _h('Пополнения и выплаты по месяцам'),
            if (report.depositsByMonth.isNotEmpty) ...[
              _label('Пополнения · ${Fmt.money(report.depositsByMonth.values.fold(0.0, (a, b) => a + b))}'),
              _monthChart(report.depositsByMonth, _violet),
              pw.SizedBox(height: 10),
            ],
            if (report.payoutsByMonth.isNotEmpty) ...[
              _label('Выплаты · ${Fmt.money(report.payoutsRub)}'),
              _monthChart(report.payoutsByMonth, _positive),
            ],
          ],

          // --- Выплаты по бумагам ---
          if (report.payoutEvents.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _h('Выплаты по бумагам'),
            _payoutsTable(report),
          ],

          // --- Секторы ---
          if (report.bySector.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _h('Секторы на конец года'),
            _sectorBars(report.bySector),
          ],

          // --- Бумаги ---
          pw.SizedBox(height: 22),
          _h('Бумаги за год'),
          _table(report.rows),

          // --- Все сделки ---
          if (report.trades.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _h('Все сделки'),
            _eventsTable([
              for (final e in report.trades)
                [
                  Fmt.date(e.date),
                  e.name,
                  e.isSell ? 'Продажа' : 'Покупка',
                  '${e.isSell ? '+' : '−'}${Fmt.money(e.rub)}',
                ],
            ], ['Дата', 'Бумага', 'Операция', 'Сумма']),
          ],
          if (report.payoutEvents.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _h('Все выплаты'),
            _eventsTable([
              for (final e in report.payoutEvents) [Fmt.date(e.date), e.name, '', '+${Fmt.money(e.rub)}'],
            ], ['Дата', 'Бумага', '', 'Получено']),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _h(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _label(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      );

  static pw.Widget _kv(String k, String v, {PdfColor? color, bool bold = false, bool top = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
        decoration: top ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))) : null,
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontSize: 9, color: bold ? PdfColors.black : _muted))),
            pw.Text(v,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color,
                )),
          ],
        ),
      );

  static pw.Widget _grid(List<(String, String, PdfColor?)> cells) => pw.Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          for (final (k, v, c) in cells)
            pw.SizedBox(
              width: 150,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(k, style: const pw.TextStyle(fontSize: 8, color: _muted)),
                  pw.SizedBox(height: 2),
                  pw.Text(v, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: c)),
                ],
              ),
            ),
        ],
      );

  static pw.Widget _monthAxis() => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [for (final m in _monthsShort) pw.Text(m, style: const pw.TextStyle(fontSize: 6.5, color: _muted))],
        ),
      );

  /// Линия стоимости — векторная, тонкая.
  static pw.Widget _lineChart(List<double> values, PdfColor color, {double height = 90}) {
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    return pw.SizedBox(
      height: height,
      child: pw.CustomPaint(
        // Ширина страницы A4 без полей.
        size: PdfPoint(515, height),
        painter: (canvas, size) {
          canvas
            ..setStrokeColor(color)
            ..setLineWidth(1.4);
          for (var i = 0; i < values.length; i++) {
            final x = size.x * i / (values.length - 1);
            final y = 4 + (values[i] - lo) / span * (size.y - 8);
            if (i == 0) {
              canvas.moveTo(x, y);
            } else {
              canvas.lineTo(x, y);
            }
          }
          canvas.strokePath();
        },
      ),
    );
  }

  static pw.Widget _payoutsTable(AnnualReport report) {
    final count = <String, int>{};
    final sum = <String, double>{};
    final names = <String, String>{};
    for (final e in report.payoutEvents) {
      count[e.ticker] = (count[e.ticker] ?? 0) + 1;
      sum[e.ticker] = (sum[e.ticker] ?? 0) + e.rub;
      names[e.ticker] = e.name;
    }
    final keys = sum.keys.toList()..sort((a, b) => sum[b]!.compareTo(sum[a]!));
    return _eventsTable([
      for (final k in keys)
        [names[k]!, '${count[k]}', '${(sum[k]! / report.payoutsRub * 100).round()}%', Fmt.money(sum[k]!)],
      ['Итого', '${report.payoutEvents.length}', '100%', Fmt.money(report.payoutsRub)],
    ], ['Бумага', 'Выплат', 'Доля', 'Получено']);
  }

  static pw.Widget _eventsTable(List<List<String>> rows, List<String> head) {
    pw.Widget c(String t, {bool left = false, bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
          child: pw.Text(
            t,
            textAlign: left ? pw.TextAlign.left : pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
          ),
        );
    PdfColor? tone(String v) => v.startsWith('+') ? _positive : (v.startsWith('−') ? _negative : null);
    return pw.Table(
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.6)),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(children: [
          for (int i = 0; i < head.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4, left: 2, right: 2),
              child: pw.Text(head[i],
                  textAlign: i <= 1 ? pw.TextAlign.left : pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ),
        ]),
        for (final r in rows)
          pw.TableRow(children: [
            for (int i = 0; i < r.length; i++) c(r[i], left: i <= 1, color: i == r.length - 1 ? tone(r[i]) : null),
          ]),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    );
  }

  /// Столбики по месяцам. Рисуем прямоугольниками: так диаграмма остаётся
  /// векторной и читается при печати.
  static pw.Widget _monthChart(Map<int, double> byMonth, PdfColor color) {
    const labels = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final maxValue = byMonth.values.fold(0.0, (a, b) => b > a ? b : a);
    if (maxValue <= 0) return pw.SizedBox();

    return pw.Container(
      height: 110,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          for (int m = 1; m <= 12; m++)
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    (byMonth[m] ?? 0) > 0 ? Fmt.compact(byMonth[m]!) : '',
                    style: const pw.TextStyle(fontSize: 6, color: _muted),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    height: 76 * ((byMonth[m] ?? 0) / maxValue),
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(labels[m - 1], style: const pw.TextStyle(fontSize: 7, color: _muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Доля в тысячных для flex-весов: целочисленный вес — единственный способ
  /// задать пропорцию внутри Row.
  static int _weight(double fraction) => (fraction * 1000).round().clamp(1, 1000);

  static pw.Widget _sectorBars(Map<String, double> bySector) {
    final total = bySector.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return pw.SizedBox();
    final entries = bySector.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return pw.Column(
      children: [
        for (final e in entries)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 130, child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 9))),
                // Доля рисуется через flex: в pdf нет FractionallySizedBox,
                // а Row с весами даёт тот же результат и не требует знать
                // ширину заранее.
                pw.Expanded(
                  child: pw.Container(
                    height: 10,
                    decoration: pw.BoxDecoration(
                      color: _line,
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: _weight(e.value / total),
                          child: pw.Container(
                            decoration: pw.BoxDecoration(
                              color: _accent,
                              borderRadius: pw.BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        if (_weight(e.value / total) < 1000)
                          pw.Expanded(flex: 1000 - _weight(e.value / total), child: pw.SizedBox()),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.SizedBox(
                  width: 74,
                  child: pw.Text(
                    '${(e.value / total * 100).toStringAsFixed(1)}%  ${Fmt.compact(e.value)}',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Сделки по месяцам таблицей: куплено, продано и сколько на самом деле
  /// вложено в бумаги. Одни покупки без продаж вводили в заблуждение, а
  /// отрицательный итог месяца столбиком не нарисовать.
  static pw.Widget _tradesByMonth(AnnualReport report) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    pw.Widget cell(String text, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );
    }

    double boughtTotal = 0;
    double soldTotal = 0;
    final rows = <pw.TableRow>[];
    for (int m = 1; m <= 12; m++) {
      final bought = report.boughtByMonth[m] ?? 0;
      final sold = report.soldByMonth[m] ?? 0;
      if (bought <= 0 && sold <= 0) continue;
      boughtTotal += bought;
      soldTotal += sold;
      final net = bought - sold;
      rows.add(pw.TableRow(children: [
        cell(months[m - 1], align: pw.TextAlign.left),
        cell(bought > 0 ? Fmt.money(bought) : '—'),
        cell(sold > 0 ? Fmt.money(sold) : '—', color: sold > 0 ? _negative : null),
        cell(Fmt.signedMoney(net), bold: true, color: net < 0 ? _negative : null),
      ]));
    }
    final netTotal = boughtTotal - soldTotal;

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line),
        bottom: pw.BorderSide(color: _line),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4F6FA)),
          children: [
            cell('Месяц', bold: true, align: pw.TextAlign.left),
            cell('Куплено', bold: true),
            cell('Продано', bold: true),
            cell('Вложено', bold: true),
          ],
        ),
        ...rows,
        pw.TableRow(
          children: [
            cell('За год', bold: true, align: pw.TextAlign.left),
            cell(Fmt.money(boughtTotal), bold: true),
            cell(Fmt.money(soldTotal), bold: true, color: soldTotal > 0 ? _negative : null),
            cell(Fmt.signedMoney(netTotal), bold: true, color: netTotal < 0 ? _negative : null),
          ],
        ),
      ],
    );
  }

  static pw.Widget _table(List<ReportRow> rows) {
    pw.Widget cell(String text, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
        ),
      );
    }

    String m(double v) => v == 0 ? '—' : Fmt.compact(v);
    return pw.Table(
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.6)),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.6),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(1.3),
        7: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          for (final (i, h) in ['Бумага', 'На 1 янв', 'Куплено', 'Продано', 'На конец', 'Выплаты', 'Итог', '%'].indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4, left: 2, right: 2),
              child: pw.Text(h,
                  textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ),
        ]),
        for (final r in rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(r.name, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    [
                      r.ticker,
                      if (r.redeemed) 'погашена' else if (r.isClosed) 'закрыта',
                      if (!r.isClosed && !r.redeemed) '${Fmt.qty(r.qtyEnd)} шт',
                    ].join(' · '),
                    style: const pw.TextStyle(fontSize: 6.5, color: _muted),
                  ),
                ],
              ),
            ),
            cell(m(r.valueStartRub)),
            cell(m(r.boughtSumRub)),
            cell(m(r.soldSumRub)),
            cell(m(r.valueRub), bold: true),
            cell(r.payoutsRub > 0 ? Fmt.compact(r.payoutsRub) : '—', color: r.payoutsRub > 0 ? _positive : null),
            cell(Fmt.signedMoney(r.totalResultRub), color: _pnl(r.totalResultRub)),
            cell(r.valueStartRub + r.boughtSumRub > 0 ? Fmt.pct(r.yieldPct) : '—', color: _pnl(r.yieldPct)),
          ]),
      ],
    );
  }
}
