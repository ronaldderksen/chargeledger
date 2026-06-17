import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../data/zaptec_api.dart';
import '../domain/history_periods.dart';
import '../domain/models.dart';
import '../storage/charge_repository.dart';
import '../storage/postgres_schema.dart';

class PostgresChargeRepository implements ChargeRepository {
  PostgresChargeRepository({
    required Connection connection,
    ZaptecApi? zaptecApi,
    Uuid? uuid,
  }) : _conn = connection,
       _zaptecApi = zaptecApi ?? ZaptecApi(),
       _uuid = uuid ?? const Uuid();

  final Connection _conn;
  final ZaptecApi _zaptecApi;
  final Uuid _uuid;

  @override
  Future<void> initialize() => checkPostgresDatabase(_conn);

  @override
  Future<ZaptecSession?> loadSession() async {
    final Result rows = await _conn.execute(
      "select key, value from schema_state where key in "
      "('session.customer_id', 'session.email', 'session.access_token', "
      "'session.expires_at')",
    );
    final Map<String, String> values = <String, String>{
      for (final ResultRow row in rows) row[0] as String: row[1] as String,
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
    final String customerId = await _ensureCustomer(email);
    final int expiresIn = (token['expires_in'] as num?)?.toInt() ?? 3600;
    final ZaptecSession session = ZaptecSession(
      customerId: customerId,
      email: email.trim().toLowerCase(),
      accessToken: token['access_token'].toString(),
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<void> logout() async {
    await _conn.execute("delete from schema_state where key like 'session.%'");
  }

  @override
  Future<List<Charger>> syncChargers() async {
    final ZaptecSession session = await _requireSession();
    final List<Charger> chargers = await _zaptecApi.loadChargers(
      session.accessToken,
    );
    for (final Charger charger in chargers) {
      await _conn.execute(
        Sql.named(
          'insert into zaptec_chargers '
          '(customer_id, id, name, serial_number, installation_id, updated_at) '
          'values (@customerId, @id, @name, @serialNumber, @installationId, now()) '
          'on conflict (customer_id, id) do update set '
          'name = excluded.name, serial_number = excluded.serial_number, '
          'installation_id = excluded.installation_id, updated_at = now()',
        ),
        parameters: <String, Object?>{
          'customerId': session.customerId,
          'id': charger.id,
          'name': charger.name,
          'serialNumber': charger.serialNumber,
          'installationId': charger.installationId,
        },
      );
    }
    return loadChargers();
  }

  @override
  Future<List<Charger>> loadChargers() async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      return const <Charger>[];
    }
    final Result rows = await _conn.execute(
      Sql.named(
        'select id, coalesce(name, serial_number, id), serial_number, installation_id '
        'from zaptec_chargers where customer_id = @customerId '
        'order by coalesce(name, serial_number, id)',
      ),
      parameters: <String, Object?>{'customerId': session.customerId},
    );
    return rows
        .map(
          (ResultRow row) => Charger(
            id: row[0] as String,
            name: row[1] as String,
            serialNumber: row[2] as String?,
            installationId: row[3] as String?,
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
    for (final ChargeSession item in sessions) {
      await _conn.execute(
        Sql.named(
          'insert into charge_history '
          '(customer_id, id, charger_id, user_name, start_time, end_time, '
          'energy_kwh, duration_seconds, cost, updated_at) '
          'values (@customerId, @id, @chargerId, @userName, @startTime, '
          '@endTime, @energyKwh, @durationSeconds, @cost, now()) '
          'on conflict (customer_id, id) do update set '
          'charger_id = excluded.charger_id, user_name = excluded.user_name, '
          'start_time = excluded.start_time, end_time = excluded.end_time, '
          'energy_kwh = excluded.energy_kwh, '
          'duration_seconds = excluded.duration_seconds, cost = excluded.cost, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{
          'customerId': session.customerId,
          'id': item.id,
          'chargerId': item.chargerId,
          'userName': item.userName,
          'startTime': item.startTime,
          'endTime': item.endTime,
          'energyKwh': item.energyKwh,
          'durationSeconds': item.durationSeconds,
          'cost': item.cost,
        },
      );
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
    final Result rows = await _conn.execute(
      Sql.named(
        'select charge_history.id, charge_history.charger_id, '
        'coalesce(zaptec_chargers.name, zaptec_chargers.serial_number, '
        'charge_history.charger_id) as charger_name, charge_history.user_name, '
        'charge_history.start_time, charge_history.end_time, '
        'charge_history.energy_kwh, charge_history.duration_seconds, '
        'charge_history.cost from charge_history left join zaptec_chargers '
        'on zaptec_chargers.customer_id = charge_history.customer_id '
        'and zaptec_chargers.id = charge_history.charger_id '
        '${where.sql} '
        'order by coalesce(charge_history.start_time, charge_history.end_time, '
        'charge_history.created_at) desc limit 100',
      ),
      parameters: where.parameters,
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
    final Result rows = await _conn.execute(
      Sql.named(
        'select count(*), sum(energy_kwh), sum(duration_seconds), sum(cost) '
        'from charge_history ${where.sql}',
      ),
      parameters: where.parameters,
    );
    final ResultRow row = rows.first;
    return HistoryTotals(
      sessions: (row[0] as num?)?.toInt() ?? 0,
      energyKwh: (row[1] as num?)?.toDouble(),
      durationSeconds: (row[2] as num?)?.toInt(),
      cost: (row[3] as num?)?.toDouble(),
    );
  }

  Future<String> _ensureCustomer(String email) async {
    final String customerId = _uuid.v4();
    final Result rows = await _conn.execute(
      Sql.named(
        'insert into customers (id, email, updated_at) '
        'values (@id, @email, now()) '
        'on conflict (email) do update set updated_at = now() returning id',
      ),
      parameters: <String, Object?>{
        'id': customerId,
        'email': email.trim().toLowerCase(),
      },
    );
    return rows.first[0] as String;
  }

  Future<void> _saveSession(ZaptecSession session) async {
    for (final MapEntry<String, String> entry in <String, String>{
      'session.customer_id': session.customerId,
      'session.email': session.email,
      'session.access_token': session.accessToken,
      'session.expires_at': session.expiresAt.toUtc().toIso8601String(),
    }.entries) {
      await _conn.execute(
        Sql.named(
          'insert into schema_state (key, value, updated_at) '
          'values (@key, @value, now()) '
          'on conflict (key) do update set value = excluded.value, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{'key': entry.key, 'value': entry.value},
      );
    }
  }

  Future<ZaptecSession> _requireSession() async {
    final ZaptecSession? session = await loadSession();
    if (session == null) {
      throw StateError('No valid Zaptec login is available.');
    }
    return session;
  }

  _Where _historyWhere(String customerId, HistoryFilter filter) {
    final Map<String, Object?> parameters = <String, Object?>{
      'customerId': customerId,
    };
    final StringBuffer sql = StringBuffer(
      'where charge_history.customer_id = @customerId',
    );
    if (filter.chargerId?.isNotEmpty == true) {
      sql.write(' and charge_history.charger_id = @chargerId');
      parameters['chargerId'] = filter.chargerId;
    }
    final bounds = periodBounds(filter);
    final String timeField = filter.timeField == HistoryTimeField.endTime
        ? 'charge_history.end_time'
        : 'charge_history.start_time';
    if (bounds.start != null) {
      sql.write(' and $timeField >= @startTime');
      parameters['startTime'] = bounds.start;
    }
    if (bounds.end != null) {
      sql.write(' and $timeField < @endTime');
      parameters['endTime'] = bounds.end;
    }
    return _Where(sql.toString(), parameters);
  }

  ChargeSession _sessionFromRow(ResultRow row) {
    return ChargeSession(
      id: row[0] as String,
      chargerId: row[1] as String?,
      chargerName: row[2] as String?,
      userName: row[3] as String?,
      startTime: _asDate(row[4]),
      endTime: _asDate(row[5]),
      energyKwh: (row[6] as num?)?.toDouble(),
      durationSeconds: (row[7] as num?)?.toInt(),
      cost: (row[8] as num?)?.toDouble(),
    );
  }
}

class _Where {
  const _Where(this.sql, this.parameters);

  final String sql;
  final Map<String, Object?> parameters;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
