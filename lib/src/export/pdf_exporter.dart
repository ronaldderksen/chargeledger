import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/formatters.dart';
import '../domain/history_periods.dart';
import '../domain/models.dart';

class ChargeHistoryPdfSelection {
  const ChargeHistoryPdfSelection({
    required this.filter,
    required this.chargers,
    required this.sessions,
    required this.totals,
    required this.columns,
    required this.currencyCode,
  });

  final HistoryFilter filter;
  final List<Charger> chargers;
  final List<ChargeSession> sessions;
  final HistoryTotals totals;
  final List<HistoryColumn> columns;
  final String currencyCode;
}

class ChargeHistoryPdf {
  const ChargeHistoryPdf({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

Future<ChargeHistoryPdf> buildChargeHistoryPdf(
  ChargeHistoryPdfSelection selection,
) async {
  final pw.Document document = pw.Document();
  final PdfColor primary = PdfColor.fromHex('#24745b');
  final PdfColor border = PdfColor.fromHex('#d7ded9');
  final PdfColor muted = PdfColor.fromHex('#56635c');
  final DateTime generatedAt = DateTime.now();
  final pw.ThemeData theme = pw.ThemeData.withFont();
  final pw.Font? currencySymbolFont = selection.currencyCode.contains('€')
      ? await PdfGoogleFonts.notoSansRegular()
      : null;

  document.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
      ),
      footer: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border)),
          ),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(color: muted, fontSize: 9),
          ),
        );
      },
      build: (pw.Context context) => <pw.Widget>[
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              'Charge Ledger',
              style: pw.TextStyle(
                color: primary,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Charge sessions export',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        _sectionTitle('Selection', primary),
        _selectionTable(selection, border, muted),
        pw.SizedBox(height: 16),
        _sectionTitle('Totals', primary),
        _totalsRow(selection, currencySymbolFont),
        pw.SizedBox(height: 20),
        _sectionTitle('Charge Sessions', primary),
        if (selection.sessions.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: border),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text('No stored charge sessions for this selection.'),
          )
        else
          _sessionsTable(selection, border, currencySymbolFont),
      ],
    ),
  );

  final Uint8List bytes = await document.save();
  return ChargeHistoryPdf(
    bytes: bytes,
    filename: _pdfFileName(selection, generatedAt),
  );
}

pw.Widget _sectionTitle(String text, PdfColor color) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _selectionTable(
  ChargeHistoryPdfSelection selection,
  PdfColor border,
  PdfColor muted,
) {
  final List<(String, String)> rows = <(String, String)>[
    ('Charger', _chargerLabel(selection)),
    ('Period', _periodLabel(selection.filter)),
    ('Time field', _timeFieldLabel(selection.filter.timeField)),
    ('Rows', selection.sessions.length.toString()),
  ];
  return pw.Table(
    border: pw.TableBorder.all(color: border),
    columnWidths: const <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(90),
      1: pw.FlexColumnWidth(),
    },
    children: <pw.TableRow>[
      for (final (String label, String value) in rows)
        pw.TableRow(
          children: <pw.Widget>[
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _totalsRow(
  ChargeHistoryPdfSelection selection,
  pw.Font? currencySymbolFont,
) {
  final List<(String, pw.Widget)> totals = <(String, pw.Widget)>[
    (
      'Sessions',
      pw.Text(
        selection.totals.sessions.toString(),
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ),
    (
      'Energy',
      pw.Text(
        '${displayNumber(selection.totals.energyKwh)} kWh',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ),
    (
      'Duration',
      pw.Text(
        displayDuration(selection.totals.durationSeconds),
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ),
    (
      'Cost',
      _moneyText(
        selection.totals.cost,
        selection.currencyCode,
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        currencySymbolFont: currencySymbolFont,
        fixedWidth: false,
      ),
    ),
  ];
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      for (final (String label, pw.Widget value) in totals)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#f6f8f7'),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#56635c'),
                    fontSize: 9,
                  ),
                ),
                pw.SizedBox(height: 4),
                value,
              ],
            ),
          ),
        ),
    ],
  );
}

pw.Widget _sessionsTable(
  ChargeHistoryPdfSelection selection,
  PdfColor border,
  pw.Font? currencySymbolFont,
) {
  final List<HistoryColumn> columns = selection.columns.isEmpty
      ? HistoryColumn.values
      : selection.columns;
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: border, width: 0.5),
    columnWidths: _sessionColumnWidths(columns),
    headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#e8eeea')),
    headerAlignments: _sessionColumnAlignments(columns),
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    cellAlignments: _sessionColumnAlignments(columns),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    headers: <String>[
      for (final HistoryColumn column in columns) _columnLabel(column),
    ],
    data: <List<Object>>[
      for (final ChargeSession session in selection.sessions)
        <Object>[
          for (final HistoryColumn column in columns)
            if (column == HistoryColumn.cost)
              _moneyText(
                session.cost,
                selection.currencyCode,
                fontSize: 8,
                currencySymbolFont: currencySymbolFont,
                fixedWidth: true,
              )
            else
              _columnValue(column, session, selection.currencyCode),
        ],
    ],
  );
}

pw.Widget _moneyText(
  num? value,
  String currencyCode, {
  required double fontSize,
  pw.FontWeight? fontWeight,
  pw.Font? currencySymbolFont,
  required bool fixedWidth,
}) {
  final String currency = currencyCode.trim().toUpperCase();
  if (value == null) {
    return pw.Text(
      '-',
      style: pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight),
    );
  }
  final bool usesFallbackCurrencyFont =
      currency == '€' && currencySymbolFont != null;
  if (!fixedWidth) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Text(
          currency,
          style: pw.TextStyle(
            font: usesFallbackCurrencyFont ? currencySymbolFont : null,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        pw.SizedBox(width: 3),
        pw.Text(
          displayNumber(value),
          style: pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        ),
      ],
    );
  }
  return pw.SizedBox(
    width: fontSize <= 8 ? 58 : 62,
    child: pw.Row(
      children: <pw.Widget>[
        pw.SizedBox(
          width: fontSize <= 8 ? 18 : 16,
          child: pw.Text(
            currency,
            textAlign: pw.TextAlign.left,
            style: pw.TextStyle(
              font: usesFallbackCurrencyFont ? currencySymbolFont : null,
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          ),
        ),
        pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Text(
            displayNumber(value),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight),
          ),
        ),
      ],
    ),
  );
}

Map<int, pw.TableColumnWidth> _sessionColumnWidths(
  List<HistoryColumn> columns,
) {
  return <int, pw.TableColumnWidth>{
    for (int index = 0; index < columns.length; index++)
      index: switch (columns[index]) {
        HistoryColumn.start ||
        HistoryColumn.end => const pw.FixedColumnWidth(92),
        HistoryColumn.charger => const pw.FlexColumnWidth(1.4),
        HistoryColumn.user => const pw.FlexColumnWidth(1.1),
        HistoryColumn.energy => const pw.FixedColumnWidth(52),
        HistoryColumn.duration => const pw.FixedColumnWidth(62),
        HistoryColumn.cost => const pw.FixedColumnWidth(72),
      },
  };
}

Map<int, pw.AlignmentGeometry> _sessionColumnAlignments(
  List<HistoryColumn> columns,
) {
  return <int, pw.AlignmentGeometry>{
    for (int index = 0; index < columns.length; index++)
      if (columns[index] == HistoryColumn.energy ||
          columns[index] == HistoryColumn.cost)
        index: pw.Alignment.centerRight,
  };
}

String _chargerLabel(ChargeHistoryPdfSelection selection) {
  final String? chargerId = selection.filter.chargerId;
  if (chargerId == null || chargerId.isEmpty) {
    return 'All chargers';
  }
  for (final Charger charger in selection.chargers) {
    if (charger.id == chargerId) {
      return charger.name;
    }
  }
  return chargerId;
}

String _periodLabel(HistoryFilter filter) {
  return switch (filter.period) {
    HistoryPeriod.all => 'All',
    HistoryPeriod.year ||
    HistoryPeriod.quarter ||
    HistoryPeriod.month ||
    HistoryPeriod.week => _periodDateRange(filter),
    HistoryPeriod.custom =>
      '${displayDate(filter.startDate)} - ${displayDate(filter.endDate)}',
  };
}

String _periodDateRange(HistoryFilter filter) {
  final ({DateTime? end, DateTime? start}) bounds = periodBounds(filter);
  final DateTime? start = bounds.start;
  final DateTime? end = bounds.end;
  if (start == null || end == null) {
    return '';
  }
  return '${displayDate(start)} - ${displayDate(end.subtract(const Duration(days: 1)))}';
}

String _timeFieldLabel(HistoryTimeField field) {
  return switch (field) {
    HistoryTimeField.startTime => 'Start time',
    HistoryTimeField.endTime => 'End time',
  };
}

String _columnLabel(HistoryColumn column) {
  return switch (column) {
    HistoryColumn.start => 'Start',
    HistoryColumn.end => 'End',
    HistoryColumn.charger => 'Charger',
    HistoryColumn.user => 'User',
    HistoryColumn.energy => 'kWh',
    HistoryColumn.duration => 'Duration',
    HistoryColumn.cost => 'Cost',
  };
}

String _columnValue(
  HistoryColumn column,
  ChargeSession session,
  String currencyCode,
) {
  return switch (column) {
    HistoryColumn.start => displayDateTime(session.startTime),
    HistoryColumn.end => displayDateTime(session.endTime),
    HistoryColumn.charger => displayText(
      session.chargerName ?? session.chargerId,
    ),
    HistoryColumn.user => displayText(session.userName),
    HistoryColumn.energy => displayNumber(session.energyKwh),
    HistoryColumn.duration => displayDuration(session.durationSeconds),
    HistoryColumn.cost => displayMoney(session.cost, currencyCode),
  };
}

String _pdfFileName(ChargeHistoryPdfSelection selection, DateTime generatedAt) {
  final String period = _periodLabel(
    selection.filter,
  ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final String date = displayDate(generatedAt);
  return 'chargeledger-$period-$date.pdf';
}
