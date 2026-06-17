import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:yaml/yaml.dart';

import 'package:chargeledger/src/domain/models.dart';
import 'package:chargeledger/src/server/postgres_charge_repository.dart';

Future<void> main(List<String> args) async {
  final ServerConfig config = await ServerConfig.load();
  final Connection conn = await _openPostgres(config);
  final PostgresChargeRepository repository = PostgresChargeRepository(
    connection: conn,
  );
  await repository.initialize();

  final Handler appHandler = Cascade()
      .add(_router(repository).call)
      .add(_staticHandler(config.webRoot))
      .handler;

  final Handler handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(_jsonErrors())
      .addHandler(appHandler);

  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln(
    'ChargeLedger server listening on http://localhost:${server.port}',
  );
}

Future<Connection> _openPostgres(ServerConfig config) async {
  final Endpoint endpoint = Endpoint(
    host: config.postgresHost,
    port: config.postgresPort,
    database: config.postgresDatabase,
    username: config.postgresUser,
    password: config.postgresPassword,
  );

  try {
    return await Connection.open(
      endpoint,
      settings: ConnectionSettings(sslMode: SslMode.require),
    );
  } on Object catch (error) {
    if (!error.toString().contains('does not support SSL')) {
      rethrow;
    }
    stderr.writeln(
      'Postgres server does not support SSL; retrying without encryption.',
    );
    return Connection.open(
      endpoint,
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
  }
}

Handler _staticHandler(String webRoot) {
  final Directory directory = Directory(webRoot);
  if (!directory.existsSync()) {
    return (Request request) => Response.notFound('Web build not found.');
  }
  return createStaticHandler(
    directory.path,
    defaultDocument: 'index.html',
    serveFilesOutsidePath: false,
  );
}

Router _router(PostgresChargeRepository repository) {
  final Router router = Router();

  router.get('/api/status', (Request request) async {
    return _json(<String, Object?>{'status': 'ok'});
  });

  router.get('/api/session', (Request request) async {
    final ZaptecSession? session = await repository.loadSession();
    return _json(<String, Object?>{'session': _sessionJson(session)});
  });

  router.post('/api/login', (Request request) async {
    final Map<String, Object?> body = await _readBody(request);
    final String email = body['email']?.toString() ?? '';
    final String password = body['password']?.toString() ?? '';
    if (email.isEmpty || password.isEmpty) {
      return _json(<String, Object?>{
        'error': 'Email and password are required.',
      }, status: 400);
    }
    final ZaptecSession session = await repository.login(email, password);
    return _json(<String, Object?>{'session': _sessionJson(session)});
  });

  router.post('/api/logout', (Request request) async {
    await repository.logout();
    return _json(<String, Object?>{'status': 'ok'});
  });

  router.get('/api/chargers', (Request request) async {
    final List<Charger> chargers = await repository.loadChargers();
    return _json(<String, Object?>{
      'chargers': chargers.map(_chargerJson).toList(),
    });
  });

  router.post('/api/chargers/sync', (Request request) async {
    final List<Charger> chargers = await repository.syncChargers();
    return _json(<String, Object?>{
      'chargers': chargers.map(_chargerJson).toList(),
    });
  });

  router.post('/api/history/sync', (Request request) async {
    final Map<String, Object?> body = await _readBody(request);
    final String? chargerId = _blankToNull(body['chargerId']?.toString());
    final int count = await repository.syncChargeHistory(chargerId: chargerId);
    return _json(<String, Object?>{'count': count});
  });

  router.get('/api/history', (Request request) async {
    final HistoryFilter filter = _filterFromQuery(request.url.queryParameters);
    final List<ChargeSession> sessions = await repository.loadChargeHistory(
      filter,
    );
    return _json(<String, Object?>{
      'sessions': sessions.map(_chargeSessionJson).toList(),
    });
  });

  router.get('/api/history/totals', (Request request) async {
    final HistoryFilter filter = _filterFromQuery(request.url.queryParameters);
    final HistoryTotals totals = await repository.loadHistoryTotals(filter);
    return _json(<String, Object?>{'totals': _totalsJson(totals)});
  });

  return router;
}

Middleware _jsonErrors() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on Object catch (error, stackTrace) {
        stderr.writeln(error);
        stderr.writeln(stackTrace);
        return _json(<String, Object?>{'error': error.toString()}, status: 500);
      }
    };
  };
}

Future<Map<String, Object?>> _readBody(Request request) async {
  final String raw = await request.readAsString();
  if (raw.trim().isEmpty) {
    return <String, Object?>{};
  }
  return Map<String, Object?>.from(jsonDecode(raw) as Map);
}

HistoryFilter _filterFromQuery(Map<String, String> query) {
  return HistoryFilter(
    period: HistoryPeriod.values.firstWhere(
      (HistoryPeriod value) => value.name == query['period'],
      orElse: () => HistoryPeriod.all,
    ),
    timeField: HistoryTimeField.values.firstWhere(
      (HistoryTimeField value) => value.name == query['timeField'],
      orElse: () => HistoryTimeField.startTime,
    ),
    periodValue: _blankToNull(query['periodValue']),
    startDate: _parseDate(query['startDate']),
    endDate: _parseDate(query['endDate']),
    chargerId: _blankToNull(query['chargerId']),
  );
}

Response _json(Map<String, Object?> body, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: const <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    },
  );
}

Map<String, Object?>? _sessionJson(ZaptecSession? session) {
  if (session == null) {
    return null;
  }
  return <String, Object?>{
    'customerId': session.customerId,
    'email': session.email,
    'expiresAt': session.expiresAt.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _chargerJson(Charger charger) {
  return <String, Object?>{
    'id': charger.id,
    'name': charger.name,
    'serialNumber': charger.serialNumber,
    'installationId': charger.installationId,
  };
}

Map<String, Object?> _chargeSessionJson(ChargeSession session) {
  return <String, Object?>{
    'id': session.id,
    'chargerId': session.chargerId,
    'chargerName': session.chargerName,
    'userName': session.userName,
    'startTime': session.startTime?.toUtc().toIso8601String(),
    'endTime': session.endTime?.toUtc().toIso8601String(),
    'energyKwh': session.energyKwh,
    'durationSeconds': session.durationSeconds,
    'cost': session.cost,
  };
}

Map<String, Object?> _totalsJson(HistoryTotals totals) {
  return <String, Object?>{
    'sessions': totals.sessions,
    'energyKwh': totals.energyKwh,
    'durationSeconds': totals.durationSeconds,
    'cost': totals.cost,
  };
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty || value == 'null') {
    return null;
  }
  return value.trim();
}

class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.postgresHost,
    required this.postgresPort,
    required this.postgresDatabase,
    required this.postgresUser,
    required this.postgresPassword,
    required this.webRoot,
  });

  final int port;
  final String postgresHost;
  final int postgresPort;
  final String postgresDatabase;
  final String postgresUser;
  final String postgresPassword;
  final String webRoot;

  static Future<ServerConfig> load() async {
    final String configPath =
        Platform.environment['CHARGELEDGER_CONFIG'] ??
        Platform.environment['ZAPWEB_CONFIG'] ??
        _defaultConfigPath();
    YamlMap yaml = YamlMap();
    final File file = File(configPath);
    if (await file.exists()) {
      yaml = loadYaml(await file.readAsString()) as YamlMap? ?? YamlMap();
    }
    final Object? postgresValue = yaml['postgres'];
    final YamlMap postgres = postgresValue is YamlMap
        ? postgresValue
        : YamlMap();
    return ServerConfig(
      port: int.tryParse(Platform.environment['PORT'] ?? '') ?? 8912,
      postgresHost:
          Platform.environment['POSTGRES_HOST'] ??
          postgres['host']?.toString() ??
          'localhost',
      postgresPort:
          int.tryParse(
            Platform.environment['POSTGRES_PORT'] ??
                postgres['port']?.toString() ??
                '',
          ) ??
          5432,
      postgresDatabase:
          Platform.environment['POSTGRES_DB'] ??
          postgres['db']?.toString() ??
          'zapweb',
      postgresUser:
          Platform.environment['POSTGRES_USER'] ??
          postgres['user']?.toString() ??
          'zapweb',
      postgresPassword:
          Platform.environment['POSTGRES_PASSWORD'] ??
          postgres['password']?.toString() ??
          'zapweb',
      webRoot:
          Platform.environment['CHARGELEDGER_WEB_ROOT'] ?? _defaultWebRoot(),
    );
  }
}

String _defaultWebRoot() {
  final Directory workingDirectoryBuild = Directory('build/web');
  if (workingDirectoryBuild.existsSync()) {
    return workingDirectoryBuild.absolute.path;
  }
  if (Directory('/app/build/web').existsSync()) {
    return '/app/build/web';
  }
  return '/app/web';
}

String _defaultConfigPath() {
  if (File('/app/info.yaml').existsSync()) {
    return '/app/info.yaml';
  }
  return 'info.yaml';
}
