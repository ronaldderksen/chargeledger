import 'package:chargeledger/src/domain/models.dart';
import 'package:chargeledger/src/storage/sqlite_charge_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('SQLite pages and full export preserve filtering and customer isolation', () async {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    final repository = SqliteChargeRepository(database: database);
    await repository.initialize();
    final session = await repository.login('demo', '');
    for (var index = 0; index < 205; index++) {
      database.execute('insert into charge_history (customer_id, id, charger_id, start_time, energy_kwh) values (?, ?, ?, ?, ?)', [
        session.customerId,
        index.toString().padLeft(3, '0'),
        'selected',
        '2026-01-01T00:00:00.000Z',
        2,
      ]);
    }
    database.execute('insert into charge_history (customer_id, id, charger_id) values (?, ?, ?)', [session.customerId, 'other-charger', 'other']);
    database.execute('insert into customers (id, email) values (?, ?)', ['other-customer', 'other@example.com']);
    database.execute('insert into charge_history (customer_id, id, charger_id) values (?, ?, ?)', ['other-customer', 'private', 'selected']);
    const filter = HistoryFilter(chargerId: 'selected');
    final first = await repository.loadChargeHistory(filter);
    final second = await repository.loadChargeHistory(filter, offset: 100);
    final third = await repository.loadChargeHistory(filter, offset: 200);
    final all = await repository.loadChargeHistory(filter, limit: null);
    expect(first.length, 100);
    expect(second.length, 100);
    expect(third.length, 5);
    expect([...first, ...second, ...third].map((s) => s.id), all.map((s) => s.id));
    expect(all.length, 205);
    expect(all.any((s) => s.id == 'private' || s.id == 'other-charger'), false);
    expect((await repository.loadHistoryTotals(filter)).sessions, 205);
  });
}
