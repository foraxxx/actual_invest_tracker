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

  static const _accent = PdfColor.fromInt(0xFF3DA9FC);
  static const _positive = PdfColor.fromInt(0xFF0F9D67);
  static const _negative = PdfColor.fromInt(0xFFD63B58);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE2E6EE);

  /// Собирает документ и сохраняет его в файл. Возвращает путь.
  static Future<String> save(AnnualReport report, {String? portfolioName}) async {
    final bytes = await build(report, portfolioName: portfolioName);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/otchet_${report.year}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<Uint8List> build(AnnualReport report, {String? portfolioName}) async {
    await _loadFonts();
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
    final doc = pw.Document(title: 'Итоги ${report.year}');

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Invest Tracker · страница ${context.pageNumber} из ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        build: (context) => [
          _header(report, portfolioName),
          pw.SizedBox(height: 18),
          _summary(report),
          pw.SizedBox(height: 18),
          if (report.payoutsByMonth.isNotEmpty) ...[
            _sectionTitle('Выплаты по месяцам'),
            _monthChart(report.payoutsByMonth, _positive),
            pw.SizedBox(height: 16),
          ],
          if (report.boughtByMonth.isNotEmpty) ...[
            _sectionTitle('Покупки по месяцам'),
            _monthChart(report.boughtByMonth, _accent),
            pw.SizedBox(height: 16),
          ],
          if (report.bySector.isNotEmpty) ...[
            _sectionTitle('Распределение по секторам'),
            _sectorBars(report.bySector),
            pw.SizedBox(height: 16),
          ],
          if (report.newRows.isNotEmpty) ...[
            _sectionTitle('Куплены впервые в ${report.year} году'),
            _table(report.newRows),
            pw.SizedBox(height: 16),
          ],
          if (report.oldRows.isNotEmpty) ...[
            _sectionTitle('Были в портфеле и раньше'),
            _table(report.oldRows),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(AnnualReport report, String? portfolioName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ИТОГИ ГОДА', style: const pw.TextStyle(fontSize: 9, color: _muted, letterSpacing: 2)),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('${report.year}', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 10),
            if (portfolioName != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Text(portfolioName, style: const pw.TextStyle(fontSize: 13, color: _muted)),
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 2, width: 60, color: _accent),
      ],
    );
  }

  static pw.Widget _summary(AnnualReport report) {
    final cells = <List<String>>[
      ['Вложено за год', Fmt.money(report.investedRub)],
      ['Куплено на', Fmt.money(report.boughtRub)],
      ['Продано на', Fmt.money(report.soldRub)],
      ['Выплаты получены', Fmt.money(report.payoutsRub)],
      ['Прибыль от продаж', Fmt.signedMoney(report.realizedRub)],
      ['Удержан налог', Fmt.money(report.taxPaidRub)],
      ['Стоимость бумаг', Fmt.money(report.valueEndRub)],
      ['Итог года', Fmt.signedMoney(report.totalResultRub)],
    ];

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in cells)
          pw.Container(
            width: 122,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(c[0], style: const pw.TextStyle(fontSize: 8, color: _muted)),
                pw.SizedBox(height: 3),
                pw.Text(
                  c[1],
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: c[1].startsWith('-') ? _negative : PdfColors.black,
                  ),
                ),
              ],
            ),
          ),
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

  static pw.Widget _table(List<ReportRow> rows) {
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

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line),
        bottom: pw.BorderSide(color: _line),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.3),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1.4),
        5: pw.FlexColumnWidth(1.4),
        6: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4F6FA)),
          children: [
            cell('Бумага', bold: true, align: pw.TextAlign.left),
            cell('Кол-во', bold: true),
            cell('Куплено', bold: true),
            cell('Продано', bold: true),
            cell('Выплаты', bold: true),
            cell('Реализ.', bold: true),
            cell('Стоимость', bold: true),
          ],
        ),
        for (final r in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(r.ticker, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      r.isClosed ? '${r.sector} · позиция закрыта' : r.sector,
                      style: const pw.TextStyle(fontSize: 6.5, color: _muted),
                    ),
                  ],
                ),
              ),
              cell(Fmt.qty(r.qtyEnd)),
              cell(r.boughtSumRub > 0 ? Fmt.compact(r.boughtSumRub) : '—'),
              cell(r.soldSumRub > 0 ? Fmt.compact(r.soldSumRub) : '—'),
              cell(r.payoutsRub > 0 ? Fmt.compact(r.payoutsRub) : '—',
                  color: r.payoutsRub > 0 ? _positive : null),
              cell(
                r.realizedRub != 0 ? Fmt.signedMoney(r.realizedRub) : '—',
                color: r.realizedRub == 0 ? null : (r.realizedRub > 0 ? _positive : _negative),
              ),
              cell(r.valueRub > 0 ? Fmt.compact(r.valueRub) : '—', bold: true),
            ],
          ),
      ],
    );
  }
}
