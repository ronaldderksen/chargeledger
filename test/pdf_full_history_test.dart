import 'package:chargeledger/src/domain/models.dart';
import 'package:chargeledger/src/export/pdf_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF supports full selections spanning more than the default page limit', () async {
    final sessions = List.generate(1500, (index) => ChargeSession(id: '$index', userName: 'Session $index', energyKwh: 2));
    final pdf = await buildChargeHistoryPdf(
      ChargeHistoryPdfSelection(
        filter: const HistoryFilter(),
        chargers: [],
        sessions: sessions,
        totals: const HistoryTotals(sessions: 1500, energyKwh: 3000),
        columns: [HistoryColumn.user, HistoryColumn.energy],
        currencyCode: 'EUR',
      ),
    );
    expect(pdf.bytes.take(4), [37, 80, 68, 70]);
    final content = String.fromCharCodes(pdf.bytes);
    final pageCounts = RegExp(r'/Count\s+(\d+)').allMatches(content).map((match) => int.parse(match.group(1)!));
    expect(pageCounts.any((count) => count > 20), true);
  });
}
