import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../data/zaptec_api.dart';
import '../domain/history_periods.dart';
import '../domain/models.dart';
import 'charge_repository.dart';
import 'sqlite_schema.dart';

class SqliteChargeRepository implements ChargeRepository {
  SqliteChargeRepository({
    required Database database,
    ZaptecApi? zaptecApi,
    Uuid? uuid,
  }) : _db = database,
       _zaptecApi = zaptecApi ?? ZaptecApi(),
       _uuid = uuid ?? const Uuid();

  final Database _db;
  final ZaptecApi _zaptecApi;
  final Uuid _uuid;

  @override
  Future<void> initialize() async {
    checkSqliteDatabase(_db);
  }

  @override
  Future<ZaptecSession?> loadSession() async {
    final ResultSet rows = _db.select(
      "select key, value from schema_state where key in "
      "('session.customer_id', 'session.email', 'session.access_token', "
      "'session.expires_at')",
    );
    final Map<String, String> values = <String, String>{
      for (final Row row in rows) row['key'] as String: row['value'] as String,
    };
    final String? customerId = values['session.customer_id'];
    final String? email = values['session.email'];
    final String? accessToken = values['session.access_token'];
    final DateTime? expiresAt = DateTime.tryParse(
      values['session.expires_at'] ?? '',
    );
    if (customerId == null ||
        email == null ||
        accessToken == null ||
        expiresAt == null) {
      return null;
    }
    final ZaptecSession session = ZaptecSession(
      customerId: customerId,
      email: email,
      accessToken: accessToken,
      expiresAt: expiresAt,
    );
    return session.isValid ? session : null;
  }

  @override
  Future<ZaptecSession> login(String email, String password) async {
    final Map<String, Object?> token = await _zaptecApi.requestToken(
      username: email,
      password: password,
    );
    final String customerId = _ensureCustomer(email);
    final String accessToken = token['access_token'].toString();
    final int expiresIn = (token['expires_in'] as num?)?.toInt() ?? 3600;
    final DateTime expiresAt = DateTime.now().toUtc().add(
      Duration(seconds: expiresIn),
    );
    final ZaptecSession session = ZaptecSession(
      customerId: customerId,
      email: email.trim().toLowerCase(),
      accessToken: accessToken,
      expiresAt: expiresAt,
    );
    _saveSession(session);
    return session;
  }

  @override
  Future<void> logout() async {
    final ResultSet rows = _db.select(
      "select value from schema_state where key = 'session.customer_id'",
    );
    final String? customerId = rows.isEmpty
        ? null
        : rows.first['value'] as String?;
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (customerId?.isNotEmpty == true) {
        _deleteCustomerData(customerId!);
      }
      _db.execute("delete from schema_state where key like 'session.%'");
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<Charger>> syncChargers() async {
    final ZaptecSession session = await _requireSession();
    final List<Charger> chargers = await _zaptecApi.loadChargers(
      session.accessToken,
    );
    final PreparedStatement statement = _db.prepare(
      'insert into zaptec_chargers '
      '(customer_id, id, name, serial_number, installation_id, updated_at) '
      'values (?, ?, ?, ?, ?, CURRENT_TIMESTAMP) '
      'on conflict(customer_id, id) do update set '
      'name = excluded.name, '
      'serial_number = excluded.serial_number, '
      'installation_id = excluded.installation_id, '
      'updated_at = CURRENT_TIMESTAMP',
    );
    try {
      for (final Charger charger in chargers) {
        statement.execute(<Object?>[
          session.customerId,
          charger.id,
          charger.name,
          charger.serialNumber,
          charger.installationId,
        ]);
      }
    } finally {
      statement.close();
    }
    return loadChargers();
  }

  @override
  Future<List<Charger>> loadChargers() async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      return const <Charger>[];
    }
    final ResultSet rows = _db.select(
      'select id, coalesce(name, serial_number, id) as name, '
      'serial_number, installation_id '
      'from zaptec_chargers '
      'where customer_id = ? '
      'order by coalesce(name, serial_number, id)',
      <Object?>[session.customerId],
    );
    return rows
        .map(
          (Row row) => Charger(
            id: row['id'] as String,
            name: row['name'] as String,
            serialNumber: row['serial_number'] as String?,
            installationId: row['installation_id'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<int> syncChargeHistory({String? chargerId}) async {
    final ZaptecSession session = await _requireSession();
    final List<ChargeSession> sessions = await _zaptecApi.loadChargeHistory(
      accessToken: session.accessToken,
      chargerId: chargerId,
    );
    final PreparedStatement statement = _db.prepare(
      'insert into charge_history '
      '(customer_id, id, charger_id, user_name, start_time, end_time, '
      'energy_kwh, duration_seconds, cost, updated_at) '
      'values (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP) '
      'on conflict(customer_id, id) do update set '
      'charger_id = excluded.charger_id, '
      'user_name = excluded.user_name, '
      'start_time = excluded.start_time, '
      'end_time = excluded.end_time, '
      'energy_kwh = excluded.energy_kwh, '
      'duration_seconds = excluded.duration_seconds, '
      'cost = excluded.cost, '
      'updated_at = CURRENT_TIMESTAMP',
    );
    try {
      for (final ChargeSession item in sessions) {
        statement.execute(<Object?>[
          session.customerId,
          item.id,
          item.chargerId,
          item.userName,
          _dateToSql(item.startTime),
          _dateToSql(item.endTime),
          item.energyKwh,
          item.durationSeconds,
          item.cost,
        ]);
      }
    } finally {
      statement.close();
    }
    return sessions.length;
  }

  @override
  Future<List<ChargeSession>> loadChargeHistory(HistoryFilter filter) async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      return const <ChargeSession>[];
    }
    final _Where where = _historyWhere(session.customerId, filter);
    final ResultSet rows = _db.select(
      'select charge_history.id, charge_history.charger_id, '
      'coalesce(zaptec_chargers.name, zaptec_chargers.serial_number, '
      'charge_history.charger_id) as charger_name, '
      'charge_history.user_name, charge_history.start_time, '
      'charge_history.end_time, charge_history.energy_kwh, '
      'charge_history.duration_seconds, charge_history.cost '
      'from charge_history '
      'left join zaptec_chargers '
      'on zaptec_chargers.customer_id = charge_history.customer_id '
      'and zaptec_chargers.id = charge_history.charger_id '
      '${where.sql} '
      'order by coalesce(charge_history.start_time, charge_history.end_time, '
      'charge_history.created_at) desc '
      'limit 100',
      where.parameters,
    );
    return rows.map(_sessionFromRow).toList();
  }

  @override
  Future<HistoryTotals> loadHistoryTotals(HistoryFilter filter) async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      return HistoryTotals.empty;
    }
    final _Where where = _historyWhere(session.customerId, filter);
    final ResultSet rows = _db.select(
      'select count(*) as sessions, sum(energy_kwh) as energy_kwh, '
      'sum(duration_seconds) as duration_seconds, sum(cost) as cost '
      'from charge_history ${where.sql}',
      where.parameters,
    );
    if (rows.isEmpty) {
      return HistoryTotals.empty;
    }
    final Row row = rows.first;
    return HistoryTotals(
      sessions: (row['sessions'] as int?) ?? 0,
      energyKwh: (row['energy_kwh'] as num?)?.toDouble(),
      durationSeconds: (row['duration_seconds'] as num?)?.toInt(),
      cost: (row['cost'] as num?)?.toDouble(),
    );
  }

  @override
  Future<Map<HistoryPeriod, List<String>>> loadHistoryPeriodOptions(
    HistoryFilter filter,
  ) async {
    final ZaptecSession? session = await loadSession();
    if (session == null || filter.chargerId?.isNotEmpty != true) {
      return _emptyPeriodOptions();
    }
    final String column = filter.timeField == HistoryTimeField.endTime
        ? 'end_time'
        : 'start_time';
    final ResultSet rows = _db.select(
      'select $column from charge_history '
      'where customer_id = ? and charger_id = ? and $column is not null',
      <Object?>[session.customerId, filter.chargerId],
    );
    return _periodOptionsFromDates(
      rows
          .map((Row row) => _dateFromSql(row[column] as String?))
          .whereType<DateTime>(),
    );
  }

  String _ensureCustomer(String email) {
    final String normalized = email.trim().toLowerCase();
    final ResultSet existing = _db.select(
      'select id from customers where email = ? limit 1',
      <Object?>[normalized],
    );
    if (existing.isNotEmpty) {
      final String customerId = existing.first['id'] as String;
      _db.execute(
        'update customers set updated_at = CURRENT_TIMESTAMP where id = ?',
        <Object?>[customerId],
      );
      return customerId;
    }
    final String customerId = _uuid.v4();
    _db.execute(
      'insert into customers (id, email, updated_at) values (?, ?, CURRENT_TIMESTAMP)',
      <Object?>[customerId, normalized],
    );
    return customerId;
  }

  void _saveSession(ZaptecSession session) {
    final PreparedStatement statement = _db.prepare(
      'insert into schema_state (key, value, updated_at) '
      'values (?, ?, CURRENT_TIMESTAMP) '
      'on conflict(key) do update set value = excluded.value, '
      'updated_at = CURRENT_TIMESTAMP',
    );
    try {
      for (final MapEntry<String, String> entry in <String, String>{
        'session.customer_id': session.customerId,
        'session.email': session.email,
        'session.access_token': session.accessToken,
        'session.expires_at': session.expiresAt.toUtc().toIso8601String(),
      }.entries) {
        statement.execute(<Object?>[entry.key, entry.value]);
      }
    } finally {
      statement.close();
    }
  }

  void _deleteCustomerData(String customerId) {
    for (final String tableName in <String>[
      'charger_measurements',
      'charge_history',
      'zaptec_chargers',
    ]) {
      _db.execute('delete from $tableName where customer_id = ?', <Object?>[
        customerId,
      ]);
    }
    _db.execute('delete from customers where id = ?', <Object?>[customerId]);
  }

  Future<ZaptecSession> _requireSession() async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      throw StateError('No valid Zaptec login is available.');
    }
    return session;
  }

  _Where _historyWhere(String customerId, HistoryFilter filter) {
    final List<Object?> parameters = <Object?>[customerId];
    final StringBuffer sql = StringBuffer(
      'where charge_history.customer_id = ?',
    );
    if (filter.chargerId?.isNotEmpty == true) {
      sql.write(' and charge_history.charger_id = ?');
      parameters.add(filter.chargerId);
    }
    final ({DateTime? start, DateTime? end}) bounds = periodBounds(filter);
    final String timeField = filter.timeField == HistoryTimeField.endTime
        ? 'charge_history.end_time'
        : 'charge_history.start_time';
    if (bounds.start != null) {
      sql.write(' and $timeField >= ?');
      parameters.add(_dateToSql(bounds.start));
    }
    if (bounds.end != null) {
      sql.write(' and $timeField < ?');
      parameters.add(_dateToSql(bounds.end));
    }
    return _Where(sql.toString(), parameters);
  }

  ChargeSession _sessionFromRow(Row row) {
    return ChargeSession(
      id: row['id'] as String,
      chargerId: row['charger_id'] as String?,
      chargerName: row['charger_name'] as String?,
      userName: row['user_name'] as String?,
      startTime: _dateFromSql(row['start_time'] as String?),
      endTime: _dateFromSql(row['end_time'] as String?),
      energyKwh: (row['energy_kwh'] as num?)?.toDouble(),
      durationSeconds: (row['duration_seconds'] as num?)?.toInt(),
      cost: (row['cost'] as num?)?.toDouble(),
    );
  }
}

class _Where {
  const _Where(this.sql, this.parameters);

  final String sql;
  final List<Object?> parameters;
}

String? _dateToSql(DateTime? value) => value?.toUtc().toIso8601String();

DateTime? _dateFromSql(String? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

Map<HistoryPeriod, List<String>> _periodOptionsFromDates(
  Iterable<DateTime> dates,
) {
  final Map<HistoryPeriod, Set<String>> values = <HistoryPeriod, Set<String>>{
    HistoryPeriod.year: <String>{},
    HistoryPeriod.quarter: <String>{},
    HistoryPeriod.month: <String>{},
    HistoryPeriod.week: <String>{},
  };
  for (final DateTime date in dates) {
    for (final HistoryPeriod period in values.keys) {
      values[period]!.add(periodValueForDate(period, date));
    }
  }
  return <HistoryPeriod, List<String>>{
    for (final MapEntry<HistoryPeriod, Set<String>> entry in values.entries)
      entry.key: entry.value.toList()
        ..sort((String a, String b) => b.compareTo(a)),
  };
}

Map<HistoryPeriod, List<String>> _emptyPeriodOptions() {
  return <HistoryPeriod, List<String>>{
    HistoryPeriod.year: <String>[],
    HistoryPeriod.quarter: <String>[],
    HistoryPeriod.month: <String>[],
    HistoryPeriod.week: <String>[],
  };
}
