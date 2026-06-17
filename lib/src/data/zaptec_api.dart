import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';

class ZaptecApi {
  ZaptecApi({http.Client? client}) : _client = client ?? http.Client();

  static const String tokenUrl = 'https://api.zaptec.com/oauth/token';
  static const String apiBaseUrl = 'https://api.zaptec.com';

  final http.Client _client;

  Future<Map<String, Object?>> requestToken({
    required String username,
    required String password,
  }) async {
    final http.Response response = await _client
        .post(
          Uri.parse(tokenUrl),
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{
            'grant_type': 'password',
            'username': username,
            'password': password,
            'scope': 'openid',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ZaptecException(
        'Zaptec login failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }

  Future<List<Charger>> loadChargers(String accessToken) async {
    final Object response = await _get('/api/chargers', accessToken);
    final Iterable<Object?> rawChargers = _extractList(response);
    return rawChargers
        .whereType<Map>()
        .map((Map raw) => normalizeCharger(Map<String, Object?>.from(raw)))
        .where((Charger charger) => charger.id.isNotEmpty)
        .toList();
  }

  Future<List<ChargeSession>> loadChargeHistory({
    required String accessToken,
    String? chargerId,
  }) async {
    final Uri uri = Uri.parse('$apiBaseUrl/api/chargehistory').replace(
      queryParameters: <String, String>{
        'PageSize': '100',
        'PageIndex': '0',
        'DetailLevel': '1',
        'SortDescending': 'true',
        if (chargerId != null && chargerId.isNotEmpty) 'ChargerId': chargerId,
      },
    );
    final Object response = await _getUri(uri, accessToken);
    final Iterable<Object?> rawSessions = _extractList(response);
    return rawSessions
        .whereType<Map>()
        .map(
          (Map raw) => normalizeChargeSession(Map<String, Object?>.from(raw)),
        )
        .toList();
  }

  Future<Object> _get(String path, String accessToken) {
    return _getUri(Uri.parse('$apiBaseUrl$path'), accessToken);
  }

  Future<Object> _getUri(Uri uri, String accessToken) async {
    final http.Response response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
            'User-Agent': 'ChargeLedger/0.1.0',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ZaptecException(
        'Zaptec API failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Object;
  }

  Iterable<Object?> _extractList(Object response) {
    if (response is List) {
      return response;
    }
    if (response is Map) {
      return (response['Data'] ??
              response['data'] ??
              response['Items'] ??
              response['items'] ??
              response['Sessions'] ??
              response['sessions'] ??
              const <Object?>[])
          as Iterable<Object?>;
    }
    return const <Object?>[];
  }
}

Charger normalizeCharger(Map<String, Object?> raw) {
  final String id = _firstText(raw, const <String>[
    'Id',
    'id',
    'ChargerId',
    'chargerId',
  ]);
  final String name = _firstText(raw, const <String>[
    'Name',
    'name',
    'DeviceName',
    'deviceName',
  ]);
  final String serialNumber = _firstText(raw, const <String>[
    'SerialNumber',
    'serialNumber',
    'SerialNo',
    'serialNo',
  ]);
  final String installationId = _firstText(raw, const <String>[
    'InstallationId',
    'installationId',
    'Installation',
    'installation',
  ]);
  return Charger(
    id: id,
    name: name.isNotEmpty
        ? name
        : serialNumber.isNotEmpty
        ? serialNumber
        : id,
    serialNumber: serialNumber.isEmpty ? null : serialNumber,
    installationId: installationId.isEmpty ? null : installationId,
  );
}

ChargeSession normalizeChargeSession(Map<String, Object?> raw) {
  String sessionId = _firstText(raw, const <String>[
    'Id',
    'id',
    'SessionId',
    'sessionId',
    'ChargeSessionId',
    'chargeSessionId',
  ]);
  if (sessionId.isEmpty) {
    sessionId = sha256.convert(utf8.encode(jsonEncode(raw))).toString();
  }
  return ChargeSession(
    id: sessionId,
    chargerId: _emptyToNull(
      _firstText(raw, const <String>[
        'ChargerId',
        'chargerId',
        'DeviceId',
        'deviceId',
      ]),
    ),
    userName: _emptyToNull(
      _firstText(raw, const <String>[
        'UserName',
        'userName',
        'UserFullName',
        'userFullName',
        'UserEmail',
        'userEmail',
      ]),
    ),
    startTime: _firstDateTime(raw, const <String>[
      'StartTime',
      'startTime',
      'StartDateTime',
      'startDateTime',
      'Started',
      'started',
    ]),
    endTime: _firstDateTime(raw, const <String>[
      'EndTime',
      'endTime',
      'EndDateTime',
      'endDateTime',
      'Ended',
      'ended',
    ]),
    energyKwh: _firstNumber(raw, const <String>[
      'Energy',
      'energy',
      'EnergyKwh',
      'energyKwh',
      'TotalEnergyKwh',
      'totalEnergyKwh',
      'EnergyDetails.EnergyKwh',
    ]),
    durationSeconds: _firstNumber(raw, const <String>[
      'Duration',
      'duration',
      'DurationSeconds',
      'durationSeconds',
    ])?.toInt(),
    cost: _firstNumber(raw, const <String>[
      'Cost',
      'cost',
      'Price',
      'price',
      'TotalCost',
    ]),
  );
}

String _firstText(Map<String, Object?> data, List<String> keys) {
  for (final String key in keys) {
    final Object? value = _nestedValue(data, key);
    if (value != null) {
      return value.toString();
    }
  }
  return '';
}

double? _firstNumber(Map<String, Object?> data, List<String> keys) {
  for (final String key in keys) {
    final Object? value = _nestedValue(data, key);
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
  }
  return null;
}

DateTime? _firstDateTime(Map<String, Object?> data, List<String> keys) {
  for (final String key in keys) {
    final Object? value = _nestedValue(data, key);
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(
        value.replaceAll('Z', '+00:00'),
      );
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
  }
  return null;
}

Object? _nestedValue(Map<String, Object?> data, String key) {
  Object? current = data;
  for (final String part in key.split('.')) {
    if (current is! Map) {
      return null;
    }
    current = current[part];
  }
  return current;
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;

class ZaptecException implements Exception {
  const ZaptecException(this.message);

  final String message;

  @override
  String toString() => message;
}
