import 'dart:convert';

import 'package:http/http.dart' as http;

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
    return session == null ? null : _sessionFromJson(session);
  }

  @override
  Future<ZaptecSession> login(String email, String password) async {
    final Map<String, Object?> body = await _request(
      'POST',
      '/api/login',
      body: <String, Object?>{'email': email, 'password': password},
    );
    return _sessionFromJson(Map<String, Object?>.from(body['session'] as Map));
  }

  @override
  Future<void> logout() async {
    await _request('POST', '/api/logout');
  }

  @override
  Future<List<Charger>> syncChargers() async {
    final Map<String, Object?> body = await _request(
      'POST',
      '/api/chargers/sync',
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

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final Uri uri = _baseUri.replace(
      path: path,
      queryParameters: query?.isEmpty == true ? null : query,
    );
    final http.Response response = switch (method) {
      'GET' => await _client.get(uri),
      'POST' => await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
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

ZaptecSession _sessionFromJson(Map<String, Object?> json) {
  return ZaptecSession(
    customerId: json['customerId'] as String,
    email: json['email'] as String,
    accessToken: '',
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
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
  return ChargeSession(
    id: json['id'] as String,
    chargerId: json['chargerId'] as String?,
    chargerName: json['chargerName'] as String?,
    userName: json['userName'] as String?,
    startTime: _parseDate(json['startTime']),
    endTime: _parseDate(json['endTime']),
    energyKwh: (json['energyKwh'] as num?)?.toDouble(),
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    cost: (json['cost'] as num?)?.toDouble(),
  );
}

DateTime? _parseDate(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}
