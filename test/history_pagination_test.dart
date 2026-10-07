import 'package:chargeledger/src/domain/models.dart';
import 'package:chargeledger/src/storage/charge_repository.dart';
import 'package:chargeledger/src/ui/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class HistoryRepository implements ChargeRepository {
  final records = List.generate(205, (index) => ChargeSession(id: '$index', energyKwh: 2));
  final requests = <({int? limit, int offset})>[];

  @override
  Future<List<ChargeSession>> loadChargeHistory(HistoryFilter filter, {int? limit = 100, int offset = 0}) async {
    requests.add((limit: limit, offset: offset));
    return records.skip(offset).take(limit ?? records.length).toList();
  }

  @override
  Future<HistoryTotals> loadHistoryTotals(HistoryFilter filter) async => HistoryTotals(sessions: records.length, energyKwh: 410);

  @override
  Future<Map<HistoryPeriod, List<String>>> loadHistoryPeriodOptions(HistoryFilter filter) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Pages cover the full selection and stop at its boundaries', () async {
    final repository = HistoryRepository();
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    await controller.refreshHistory();
    expect(controller.sessions.length, 100);
    expect(controller.canGoToPreviousHistoryPage, false);
    expect(controller.totals.sessions, 205);
    await controller.changeHistoryPage(-1);
    expect(repository.requests.length, 1);
    await controller.changeHistoryPage(1);
    expect(controller.sessions.first.id, '100');
    await controller.changeHistoryPage(1);
    expect(controller.sessions.map((s) => s.id), ['200', '201', '202', '203', '204']);
    expect(controller.canGoToNextHistoryPage, false);
    await controller.changeHistoryPage(1);
    expect(controller.historyPage, 2);
    await controller.changeHistoryPage(-1);
    expect(controller.sessions.first.id, '100');
    await controller.setFilter(const HistoryFilter(period: HistoryPeriod.custom));
    expect(controller.historyPage, 0);
    expect(controller.sessions.first.id, '0');
  });

  test('Export loads all rows with cost settings without changing the current page', () async {
    final repository = HistoryRepository();
    final controller = AppController(repository)..kwhPrice = 0.25;
    addTearDown(controller.dispose);
    await controller.refreshHistory();
    await controller.changeHistoryPage(1);
    final exported = await controller.loadAllHistoryForExport(controller.filter);
    expect(exported.length, 205);
    expect(exported.first.id, '0');
    expect(exported.last.id, '204');
    expect(exported.every((session) => session.cost == 0.5), true);
    expect(repository.requests.last.limit, null);
    expect(controller.historyPage, 1);
    expect(controller.sessions.first.id, '100');
  });
}
