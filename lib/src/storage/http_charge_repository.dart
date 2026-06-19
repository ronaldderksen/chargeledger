import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../domain/models.dart';
import 'charge_repository.dart';

class HttpChargeRepository implements ChargeRepository {
  HttpChargeRepository({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUri = baseUri ?? Uri.base.replace(path: '');

  final http.Client _client;
  final Uri _baseUri;

  @override
  Future<void> initialize() async {
    await _request('GET', '/api/status');
  }

  @override
  Future<ZaptecSession?> loadSession() async {
    final Map<String, Object?> body = await _request('GET', '/api/session');
    final Map<String, Object?>? session = body['session'] == null
        ? null
        : Map<String, Object?>.from(body['session'] as Map);
    if (session == null) {
      _clearClientSession();
      return null;
    }
    final ZaptecSession? mergedSession = _mergeStoredAccessToken(
      _sessionFromJson(session),
    );
    if (mergedSession == null) {
      try {
        await logout();
      } on Object {
        _clearClientSession();
      }
    }
    return mergedSession;
  }

  @override
  Future<ZaptecSession> login(String email, String password) async {
    final Map<String, Object?> body = await _request(
      'POST',
      '/api/login',
      body: <String, Object?>{'email': email, 'password': password},
    );
    final ZaptecSession session = _sessionFromJson(
      Map<String, Object?>.from(body['session'] as Map),
    );
    _saveClientSession(session);
    return session;
  }

  @override
  Future<void> logout() async {
    await _request('POST', '/api/logout');
    _clearClientSession();
  }

  @override
  Future<void> deleteStoredData() async {
    await _request('POST', '/api/server-data/delete');
    _clearClientSession();
  }

  @override
  Future<HistoryFilter?> loadFilter() async {
    final Map<String, Object?> body = await _request('GET', '/api/filter');
    final Map<String, Object?>? filter = body['filter'] == null
        ? null
        : Map<String, Object?>.from(body['filter'] as Map);
    return filter == null ? null : _filterFromJson(filter);
  }

  @override
  Future<void> saveFilter(HistoryFilter filter) async {
    await _request('POST', '/api/filter', body: _filterJson(filter));
  }

  @override
  Future<double?> loadKwhPrice() async {
    final Map<String, Object?> body = await _request('GET', '/api/settings');
    return (body['kwhPrice'] as num?)?.toDouble();
  }

  @override
  Future<void> saveKwhPrice(double? price) async {
    await _request(
      'POST',
      '/api/settings',
      body: <String, Object?>{'kwhPrice': price},
    );
  }

  @override
  Future<String?> loadCurrencyCode() async {
    final Map<String, Object?> body = await _request('GET', '/api/settings');
    return _blankToNull(body['currencyCode']?.toString());
  }

  @override
  Future<void> saveCurrencyCode(String? currencyCode) async {
    await _request(
      'POST',
      '/api/settings',
      body: <String, Object?>{'currencyCode': currencyCode},
    );
  }

  @override
  Future<List<HistoryColumn>?> loadHistoryColumns() async {
    final Map<String, Object?> body = await _request('GET', '/api/settings');
    final List<Object?>? raw = body['historyColumns'] as List<Object?>?;
    if (raw == null) {
      return null;
    }
    final List<HistoryColumn> columns = raw
        .map(
          (Object? name) => HistoryColumn.values
              .where((HistoryColumn column) => column.name == name)
              .firstOrNull,
        )
        .whereType<HistoryColumn>()
        .toList();
    return columns.isEmpty ? null : columns;
  }

  @override
  Future<void> saveHistoryColumns(List<HistoryColumn> columns) async {
    if (columns.isEmpty) {
      return;
    }
    await _request(
      'POST',
      '/api/settings',
      body: <String, Object?>{
        'historyColumns': columns
            .map((HistoryColumn column) => column.name)
            .toList(),
      },
    );
  }

  @override
  Future<List<Charger>> syncChargers() async {
    final Map<String, Object?> body = await _request(
      'POST',
      '/api/chargers/sync',
      includeAccessToken: true,
    );
    return _chargersFromJson(body['chargers'] as List? ?? const <Object?>[]);
  }

  @override
  Future<List<Charger>> loadChargers() async {
    final Map<String, Object?> body = await _request('GET', '/api/chargers');
    return _chargersFromJson(body['chargers'] as List? ?? const <Object?>[]);
  }

  @override
  Future<int> syncChargeHistory({String? chargerId}) async {
    final Map<String, Object?> body = await _request(
      'POST',
      '/api/history/sync',
      body: <String, Object?>{'chargerId': chargerId},
      includeAccessToken: true,
    );
    return (body['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<ChargeSession>> loadChargeHistory(HistoryFilter filter) async {
    final Map<String, Object?> body = await _request(
      'GET',
      '/api/history',
      query: _filterQuery(filter),
    );
    final List<Object?> sessions =
        body['sessions'] as List? ?? const <Object?>[];
    return sessions
        .whereType<Map>()
        .map(
          (Map item) => _chargeSessionFromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  @override
  Future<HistoryTotals> loadHistoryTotals(HistoryFilter filter) async {
    final Map<String, Object?> body = await _request(
      'GET',
      '/api/history/totals',
      query: _filterQuery(filter),
    );
    final Map<String, Object?> totals = Map<String, Object?>.from(
      body['totals'] as Map,
    );
    return HistoryTotals(
      sessions: (totals['sessions'] as num?)?.toInt() ?? 0,
      energyKwh: (totals['energyKwh'] as num?)?.toDouble(),
      durationSeconds: (totals['durationSeconds'] as num?)?.toInt(),
      cost: (totals['cost'] as num?)?.toDouble(),
    );
  }

  @override
  Future<Map<HistoryPeriod, List<String>>> loadHistoryPeriodOptions(
    HistoryFilter filter,
  ) async {
    final Map<String, Object?> body = await _request(
      'GET',
      '/api/history/period-options',
      query: _filterQuery(filter),
    );
    final Map<String, Object?> raw = Map<String, Object?>.from(
      body['options'] as Map,
    );
    return <HistoryPeriod, List<String>>{
      for (final HistoryPeriod period in HistoryPeriod.values)
        if (period != HistoryPeriod.all && period != HistoryPeriod.custom)
          period: List<String>.from(
            raw[period.name] as List? ?? const <Object?>[],
          ),
    };
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    bool includeAccessToken = false,
  }) async {
    final Uri uri = _baseUri.replace(
      path: path,
      queryParameters: query?.isEmpty == true ? null : query,
    );
    final Map<String, String> headers = <String, String>{
      if (includeAccessToken)
        'X-Zaptec-Access-Token': _requireClientAccessToken(),
    };
    final http.Response response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'POST' => await _client.post(
        uri,
        headers: <String, String>{
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      _ => throw ArgumentError.value(method, 'method'),
    };
    final Object? decoded = response.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'Server request failed: HTTP ${response.statusCode}';
      throw StateError(message);
    }
    return Map<String, Object?>.from(decoded as Map);
  }
}

Map<String, String> _filterQuery(HistoryFilter filter) {
  return <String, String>{
    'period': filter.period.name,
    'timeField': filter.timeField.name,
    if (filter.periodValue?.isNotEmpty == true)
      'periodValue': filter.periodValue!,
    if (filter.startDate != null)
      'startDate': filter.startDate!.toIso8601String(),
    if (filter.endDate != null) 'endDate': filter.endDate!.toIso8601String(),
    if (filter.chargerId?.isNotEmpty == true) 'chargerId': filter.chargerId!,
  };
}

Map<String, Object?> _filterJson(HistoryFilter filter) {
  return <String, Object?>{
    'period': filter.period.name,
    'timeField': filter.timeField.name,
    'periodValue': filter.periodValue,
    'startDate': filter.startDate?.toUtc().toIso8601String(),
    'endDate': filter.endDate?.toUtc().toIso8601String(),
    'chargerId': filter.chargerId,
  };
}

HistoryFilter _filterFromJson(Map<String, Object?> json) {
  return HistoryFilter(
    period: HistoryPeriod.values.firstWhere(
      (HistoryPeriod value) => value.name == json['period'],
      orElse: () => HistoryPeriod.all,
    ),
    timeField: HistoryTimeField.values.firstWhere(
      (HistoryTimeField value) => value.name == json['timeField'],
      orElse: () => HistoryTimeField.startTime,
    ),
    periodValue: _blankToNull(json['periodValue']?.toString()),
    startDate: _parseDate(json['startDate']),
    endDate: _parseDate(json['endDate']),
    chargerId: _blankToNull(json['chargerId']?.toString()),
  );
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty || value == 'null') {
    return null;
  }
  return value.trim();
}

ZaptecSession _sessionFromJson(Map<String, Object?> json) {
  return ZaptecSession(
    customerId: json['customerId'] as String,
    email: json['email'] as String,
    accessToken: json['accessToken'] as String? ?? '',
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

ZaptecSession? _mergeStoredAccessToken(ZaptecSession session) {
  final ZaptecSession? storedSession = _loadClientSession();
  if (storedSession == null ||
      storedSession.customerId != session.customerId ||
      storedSession.email != session.email ||
      storedSession.accessToken.isEmpty ||
      !storedSession.isValid) {
    _clearClientSession();
    return null;
  }
  return ZaptecSession(
    customerId: session.customerId,
    email: session.email,
    accessToken: storedSession.accessToken,
    expiresAt: session.expiresAt,
  );
}

String _requireClientAccessToken() {
  final ZaptecSession? session = _loadClientSession();
  if (session == null || !session.isValid || session.accessToken.isEmpty) {
    _clearClientSession();
    throw const LoginRequiredException();
  }
  return session.accessToken;
}

ZaptecSession? _loadClientSession() {
  final String? raw = web.window.sessionStorage.getItem('chargeledger.session');
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    return _sessionFromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  } on Object {
    _clearClientSession();
    return null;
  }
}

void _saveClientSession(ZaptecSession session) {
  web.window.sessionStorage.setItem(
    'chargeledger.session',
    jsonEncode(<String, Object?>{
      'customerId': session.customerId,
      'email': session.email,
      'accessToken': session.accessToken,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    }),
  );
}

void _clearClientSession() {
  web.window.sessionStorage.removeItem('chargeledger.session');
}

List<Charger> _chargersFromJson(List<Object?> items) {
  return items.whereType<Map>().map((Map item) {
    final Map<String, Object?> json = Map<String, Object?>.from(item);
    return Charger(
      id: json['id'] as String,
      name: json['name'] as String,
      serialNumber: json['serialNumber'] as String?,
      installationId: json['installationId'] as String?,
    );
  }).toList();
}

ChargeSession _chargeSessionFromJson(Map<String, Object?> json) {
  final DateTime? startTime = _parseDate(json['startTime']);
  final DateTime? endTime = _parseDate(json['endTime']);
  return ChargeSession(
    id: json['id'] as String,
    chargerId: json['chargerId'] as String?,
    chargerName: json['chargerName'] as String?,
    userName: json['userName'] as String?,
    startTime: startTime,
    endTime: endTime,
    energyKwh: (json['energyKwh'] as num?)?.toDouble(),
    durationSeconds:
        (json['durationSeconds'] as num?)?.toInt() ??
        _durationBetween(startTime, endTime),
    cost: (json['cost'] as num?)?.toDouble(),
  );
}

DateTime? _parseDate(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

int? _durationBetween(DateTime? startTime, DateTime? endTime) {
  if (startTime == null || endTime == null || endTime.isBefore(startTime)) {
    return null;
  }
  return endTime.difference(startTime).inSeconds;
}
