import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../data/zaptec_api.dart';
import '../domain/history_periods.dart';
import '../domain/models.dart';
import '../storage/charge_repository.dart';
import '../storage/postgres_schema.dart';

class PostgresChargeRepository implements ChargeRepository {
  PostgresChargeRepository({
    required SessionExecutor database,
    ZaptecApi? zaptecApi,
    Uuid? uuid,
  }) : _database = database,
       _zaptecApi = zaptecApi ?? ZaptecApi(),
       _uuid = uuid ?? const Uuid();

  final SessionExecutor _database;
  final ZaptecApi _zaptecApi;
  final Uuid _uuid;

  @override
  Future<void> initialize() => _database.run((Session session) async {
    await checkPostgresDatabase(session);
    await _deleteStoredAccessTokens(session);
  });

  @override
  Future<ZaptecSession?> loadSession([String? sessionId]) async {
    return _database.run((Session session) => _loadSession(session, sessionId));
  }

  Future<ZaptecSession?> _loadSession(
    Session databaseSession, [
    String? sessionId,
  ]) async {
    if (sessionId == null || sessionId.trim().isEmpty) {
      return null;
    }
    final String prefix = _sessionPrefix(sessionId);
    final Result rows = await databaseSession.execute(
      Sql.named(
        'select key, value from schema_state where key in '
        '(@customerIdKey, @emailKey, @expiresAtKey)',
      ),
      parameters: <String, Object?>{
        'customerIdKey': '${prefix}customer_id',
        'emailKey': '${prefix}email',
        'expiresAtKey': '${prefix}expires_at',
      },
    );
    final Map<String, String> values = <String, String>{
      for (final ResultRow row in rows) row[0] as String: row[1] as String,
    };
    final String? customerId = values['${prefix}customer_id'];
    final String? email = values['${prefix}email'];
    final DateTime? expiresAt = DateTime.tryParse(
      values['${prefix}expires_at'] ?? '',
    );
    if (customerId == null || email == null || expiresAt == null) {
      return null;
    }
    final ZaptecSession zaptecSession = ZaptecSession(
      customerId: customerId,
      email: email,
      accessToken: '',
      expiresAt: expiresAt,
    );
    return zaptecSession.isValid ? zaptecSession : null;
  }

  @override
  Future<ZaptecSession> login(
    String email,
    String password, [
    String? sessionId,
  ]) async {
    return _database.run((Session databaseSession) async {
      final Map<String, Object?> token = await _zaptecApi.requestToken(
        username: email,
        password: password,
      );
      final String customerId = await _ensureCustomer(databaseSession, email);
      final int expiresIn = (token['expires_in'] as num?)?.toInt() ?? 3600;
      final ZaptecSession session = ZaptecSession(
        customerId: customerId,
        email: email.trim().toLowerCase(),
        accessToken: token['access_token'].toString(),
        expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      );
      await _saveSession(databaseSession, session, sessionId);
      return session;
    });
  }

  @override
  Future<void> logout([String? sessionId]) async {
    if (sessionId == null || sessionId.trim().isEmpty) {
      return;
    }
    await _database.run((Session session) async {
      final String prefix = _sessionPrefix(sessionId);
      await session.execute(
        Sql.named('delete from schema_state where key like @sessionPrefix'),
        parameters: <String, Object?>{'sessionPrefix': '$prefix%'},
      );
    });
  }

  @override
  Future<void> deleteStoredData([String? sessionId]) async {
    if (sessionId == null || sessionId.trim().isEmpty) {
      return;
    }
    await _database.runTx((TxSession session) async {
      final ZaptecSession? zaptecSession = await _loadSession(
        session,
        sessionId,
      );
      if (zaptecSession == null) {
        return;
      }
      await _deleteCustomerData(session, zaptecSession.customerId);
      await _deleteFilter(session, zaptecSession.customerId);
      await _deleteSettings(session, zaptecSession.customerId);
      await _deleteCustomerSessions(session, zaptecSession.customerId);
    });
  }

  @override
  Future<HistoryFilter?> loadFilter([String? sessionId]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return null;
      }
      final String prefix = _filterPrefix(session.customerId);
      final Result rows = await databaseSession.execute(
        Sql.named(
          'select key, value from schema_state where key like @filterPrefix',
        ),
        parameters: <String, Object?>{'filterPrefix': '$prefix%'},
      );
      if (rows.isEmpty) {
        return null;
      }
      return _filterFromState(<String, String>{
        for (final ResultRow row in rows)
          (row[0] as String).substring(prefix.length): row[1] as String,
      });
    });
  }

  @override
  Future<void> saveFilter(HistoryFilter filter, [String? sessionId]) async {
    await _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return;
      }
      await _saveFilter(databaseSession, session.customerId, filter);
    });
  }

  @override
  Future<double?> loadKwhPrice([String? sessionId]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return null;
      }
      final Result rows = await databaseSession.execute(
        Sql.named('select value from schema_state where key = @key limit 1'),
        parameters: <String, Object?>{
          'key': _settingsKey(session.customerId, 'kwh_price'),
        },
      );
      if (rows.isEmpty) {
        return null;
      }
      return double.tryParse(rows.first[0] as String? ?? '');
    });
  }

  @override
  Future<void> saveKwhPrice(double? price, [String? sessionId]) async {
    await _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return;
      }
      final String key = _settingsKey(session.customerId, 'kwh_price');
      if (price == null) {
        await databaseSession.execute(
          Sql.named('delete from schema_state where key = @key'),
          parameters: <String, Object?>{'key': key},
        );
        return;
      }
      await databaseSession.execute(
        Sql.named(
          'insert into schema_state (key, value, updated_at) '
          'values (@key, @value, now()) '
          'on conflict (key) do update set value = excluded.value, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{'key': key, 'value': price.toString()},
      );
    });
  }

  @override
  Future<String?> loadCurrencyCode([String? sessionId]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return null;
      }
      final Result rows = await databaseSession.execute(
        Sql.named('select value from schema_state where key = @key limit 1'),
        parameters: <String, Object?>{
          'key': _settingsKey(session.customerId, 'currency_code'),
        },
      );
      if (rows.isEmpty) {
        return null;
      }
      return _blankToNull(rows.first[0] as String?);
    });
  }

  @override
  Future<void> saveCurrencyCode(
    String? currencyCode, [
    String? sessionId,
  ]) async {
    await _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return;
      }
      final String key = _settingsKey(session.customerId, 'currency_code');
      final String? normalized = _blankToNull(currencyCode?.toUpperCase());
      if (normalized == null) {
        await databaseSession.execute(
          Sql.named('delete from schema_state where key = @key'),
          parameters: <String, Object?>{'key': key},
        );
        return;
      }
      await databaseSession.execute(
        Sql.named(
          'insert into schema_state (key, value, updated_at) '
          'values (@key, @value, now()) '
          'on conflict (key) do update set value = excluded.value, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{'key': key, 'value': normalized},
      );
    });
  }

  @override
  Future<List<HistoryColumn>?> loadHistoryColumns([String? sessionId]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return null;
      }
      final Result rows = await databaseSession.execute(
        Sql.named('select value from schema_state where key = @key limit 1'),
        parameters: <String, Object?>{
          'key': _settingsKey(session.customerId, 'history_columns'),
        },
      );
      if (rows.isEmpty) {
        return null;
      }
      return _historyColumnsFromState(rows.first[0] as String?);
    });
  }

  @override
  Future<void> saveHistoryColumns(
    List<HistoryColumn> columns, [
    String? sessionId,
  ]) async {
    if (columns.isEmpty) {
      return;
    }
    await _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return;
      }
      await databaseSession.execute(
        Sql.named(
          'insert into schema_state (key, value, updated_at) '
          'values (@key, @value, now()) '
          'on conflict (key) do update set value = excluded.value, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{
          'key': _settingsKey(session.customerId, 'history_columns'),
          'value': columns.map((HistoryColumn column) => column.name).join(','),
        },
      );
    });
  }

  @override
  Future<List<Charger>> syncChargers([
    String? sessionId,
    String? accessToken,
  ]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession session = await _requireSession(
        databaseSession,
        sessionId,
      );
      final List<Charger> chargers = await _zaptecApi.loadChargers(
        _requireAccessToken(accessToken),
      );
      for (final Charger charger in chargers) {
        await databaseSession.execute(
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
      return _loadChargers(databaseSession, sessionId);
    });
  }

  @override
  Future<List<Charger>> loadChargers([String? sessionId]) async {
    return _database.run(
      (Session session) => _loadChargers(session, sessionId),
    );
  }

  Future<List<Charger>> _loadChargers(
    Session databaseSession, [
    String? sessionId,
  ]) async {
    final ZaptecSession? session = await _loadSession(
      databaseSession,
      sessionId,
    );
    if (session == null) {
      return const <Charger>[];
    }
    final Result rows = await databaseSession.execute(
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
  Future<int> syncChargeHistory({
    String? chargerId,
    String? sessionId,
    String? accessToken,
  }) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession session = await _requireSession(
        databaseSession,
        sessionId,
      );
      final List<ChargeSession> sessions = await _zaptecApi.loadChargeHistory(
        accessToken: _requireAccessToken(accessToken),
        chargerId: chargerId,
      );
      for (final ChargeSession item in sessions) {
        await databaseSession.execute(
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
    });
  }

  @override
  Future<List<ChargeSession>> loadChargeHistory(
    HistoryFilter filter, [
    String? sessionId,
  ]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return const <ChargeSession>[];
      }
      final _Where where = _historyWhere(session.customerId, filter);
      final Result rows = await databaseSession.execute(
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
    });
  }

  @override
  Future<HistoryTotals> loadHistoryTotals(
    HistoryFilter filter, [
    String? sessionId,
  ]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null) {
        return HistoryTotals.empty;
      }
      final _Where where = _historyWhere(session.customerId, filter);
      final Result rows = await databaseSession.execute(
        Sql.named(
          'select count(*), sum(energy_kwh), '
          'sum(coalesce(duration_seconds, '
          'extract(epoch from (end_time - start_time))::integer)), sum(cost) '
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
    });
  }

  @override
  Future<Map<HistoryPeriod, List<String>>> loadHistoryPeriodOptions(
    HistoryFilter filter, [
    String? sessionId,
  ]) async {
    return _database.run((Session databaseSession) async {
      final ZaptecSession? session = await _loadSession(
        databaseSession,
        sessionId,
      );
      if (session == null || filter.chargerId?.isNotEmpty != true) {
        return _emptyPeriodOptions();
      }
      final String column = filter.timeField == HistoryTimeField.endTime
          ? 'end_time'
          : 'start_time';
      final Result rows = await databaseSession.execute(
        Sql.named(
          'select $column from charge_history '
          'where customer_id = @customerId '
          'and charger_id = @chargerId '
          'and $column is not null',
        ),
        parameters: <String, Object?>{
          'customerId': session.customerId,
          'chargerId': filter.chargerId,
        },
      );
      return _periodOptionsFromDates(
        rows.map((ResultRow row) => _asDate(row[0])).whereType<DateTime>(),
      );
    });
  }

  Future<String> _ensureCustomer(Session session, String email) async {
    final String customerId = _uuid.v4();
    final Result rows = await session.execute(
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

  Future<void> _saveSession(
    Session databaseSession,
    ZaptecSession session, [
    String? sessionId,
  ]) async {
    if (sessionId == null || sessionId.trim().isEmpty) {
      throw StateError('A server session id is required.');
    }
    final String prefix = _sessionPrefix(sessionId);
    for (final MapEntry<String, String> entry in <String, String>{
      '${prefix}customer_id': session.customerId,
      '${prefix}email': session.email,
      '${prefix}expires_at': session.expiresAt.toUtc().toIso8601String(),
    }.entries) {
      await databaseSession.execute(
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

  Future<void> _deleteCustomerData(Session session, String customerId) async {
    for (final String tableName in <String>[
      'charger_measurements',
      'charge_history',
      'zaptec_chargers',
    ]) {
      await session.execute(
        Sql.named('delete from $tableName where customer_id = @customerId'),
        parameters: <String, Object?>{'customerId': customerId},
      );
    }
    await session.execute(
      Sql.named('delete from customers where id = @customerId'),
      parameters: <String, Object?>{'customerId': customerId},
    );
  }

  Future<void> _saveFilter(
    Session session,
    String customerId,
    HistoryFilter filter,
  ) async {
    final String prefix = _filterPrefix(customerId);
    for (final MapEntry<String, String> entry in _filterState(filter).entries) {
      await session.execute(
        Sql.named(
          'insert into schema_state (key, value, updated_at) '
          'values (@key, @value, now()) '
          'on conflict (key) do update set value = excluded.value, '
          'updated_at = now()',
        ),
        parameters: <String, Object?>{
          'key': '$prefix${entry.key}',
          'value': entry.value,
        },
      );
    }
  }

  Future<void> _deleteFilter(Session session, String customerId) async {
    await session.execute(
      Sql.named('delete from schema_state where key like @filterPrefix'),
      parameters: <String, Object?>{
        'filterPrefix': '${_filterPrefix(customerId)}%',
      },
    );
  }

  Future<void> _deleteSettings(Session session, String customerId) async {
    await session.execute(
      Sql.named('delete from schema_state where key like @settingsPrefix'),
      parameters: <String, Object?>{
        'settingsPrefix': '${_settingsPrefix(customerId)}%',
      },
    );
  }

  Future<void> _deleteCustomerSessions(
    Session session,
    String customerId,
  ) async {
    final Result rows = await session.execute(
      Sql.named(
        "select key from schema_state where key like 'session.%.customer_id' "
        'and value = @customerId',
      ),
      parameters: <String, Object?>{'customerId': customerId},
    );
    for (final ResultRow row in rows) {
      final String key = row[0] as String;
      final String prefix = key.substring(0, key.length - 'customer_id'.length);
      await session.execute(
        Sql.named('delete from schema_state where key like @sessionPrefix'),
        parameters: <String, Object?>{'sessionPrefix': '$prefix%'},
      );
    }
  }

  Future<void> _deleteStoredAccessTokens(Session session) async {
    await session.execute(
      "delete from schema_state where key like 'session.%.access_token'",
    );
  }

  Future<ZaptecSession> _requireSession(
    Session databaseSession,
    String? sessionId,
  ) async {
    if (sessionId == null || sessionId.trim().isEmpty) {
      throw StateError('No valid Zaptec login is available.');
    }
    final ZaptecSession? session = await _loadSession(
      databaseSession,
      sessionId,
    );
    if (session == null ||
        !await _customerExists(databaseSession, session.customerId)) {
      throw StateError('No valid Zaptec login is available.');
    }
    return session;
  }

  Future<bool> _customerExists(Session session, String customerId) async {
    final Result rows = await session.execute(
      Sql.named('select 1 from customers where id = @customerId limit 1'),
      parameters: <String, Object?>{'customerId': customerId},
    );
    return rows.isNotEmpty;
  }

  String _requireAccessToken(String? accessToken) {
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw StateError('No Zaptec access token is available on the client.');
    }
    return accessToken.trim();
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
    final DateTime? startTime = _asDate(row[4]);
    final DateTime? endTime = _asDate(row[5]);
    return ChargeSession(
      id: row[0] as String,
      chargerId: row[1] as String?,
      chargerName: row[2] as String?,
      userName: row[3] as String?,
      startTime: startTime,
      endTime: endTime,
      energyKwh: (row[6] as num?)?.toDouble(),
      durationSeconds:
          (row[7] as num?)?.toInt() ?? _durationBetween(startTime, endTime),
      cost: (row[8] as num?)?.toDouble(),
    );
  }
}

String _sessionPrefix(String? sessionId) {
  if (sessionId == null || sessionId.trim().isEmpty) {
    throw StateError('A server session id is required.');
  }
  return 'session.${sessionId.trim()}.';
}

String _filterPrefix(String customerId) => 'filter.$customerId.';

String _settingsPrefix(String customerId) => 'settings.$customerId.';

String _settingsKey(String customerId, String key) =>
    '${_settingsPrefix(customerId)}$key';

Map<String, String> _filterState(HistoryFilter filter) {
  return <String, String>{
    'period': filter.period.name,
    'time_field': filter.timeField.name,
    'period_value': filter.periodValue ?? '',
    'start_date': filter.startDate?.toUtc().toIso8601String() ?? '',
    'end_date': filter.endDate?.toUtc().toIso8601String() ?? '',
    'charger_id': filter.chargerId ?? '',
  };
}

HistoryFilter _filterFromState(Map<String, String> values) {
  return HistoryFilter(
    period: HistoryPeriod.values.firstWhere(
      (HistoryPeriod value) => value.name == values['period'],
      orElse: () => HistoryPeriod.all,
    ),
    timeField: HistoryTimeField.values.firstWhere(
      (HistoryTimeField value) => value.name == values['time_field'],
      orElse: () => HistoryTimeField.startTime,
    ),
    periodValue: _blankToNull(values['period_value']),
    startDate: _parseDate(values['start_date']),
    endDate: _parseDate(values['end_date']),
    chargerId: _blankToNull(values['charger_id']),
  );
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<HistoryColumn>? _historyColumnsFromState(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final List<HistoryColumn> columns = value
      .split(',')
      .map(
        (String name) => HistoryColumn.values
            .where((HistoryColumn column) => column.name == name.trim())
            .firstOrNull,
      )
      .whereType<HistoryColumn>()
      .toList();
  return columns.isEmpty ? null : columns;
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

int? _durationBetween(DateTime? startTime, DateTime? endTime) {
  if (startTime == null || endTime == null || endTime.isBefore(startTime)) {
    return null;
  }
  return endTime.difference(startTime).inSeconds;
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
