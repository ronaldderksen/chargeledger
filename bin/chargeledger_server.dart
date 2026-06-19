import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'package:chargeledger/src/data/zaptec_api.dart';
import 'package:chargeledger/src/domain/models.dart';
import 'package:chargeledger/src/server/postgres_charge_repository.dart';

Future<void> main(List<String> args) async {
  final ServerConfig config = await ServerConfig.load();
  final Pool<void> database = await _openPostgres(config);
  final PostgresChargeRepository repository = PostgresChargeRepository(
    database: database,
  );
  await repository.initialize();

  final Handler appHandler = Cascade()
      .add(_router(repository, config.webRoot).call)
      .add(_appStaticHandler(repository, config.webRoot))
      .handler;

  final Handler handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_securityHeaders())
      .addMiddleware(_jsonErrors())
      .addMiddleware(_requireServerSession(repository))
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

Future<Pool<void>> _openPostgres(ServerConfig config) async {
  final Endpoint endpoint = Endpoint(
    host: config.postgresHost,
    port: config.postgresPort,
    database: config.postgresDatabase,
    username: config.postgresUser,
    password: config.postgresPassword,
  );

  try {
    return await _openPostgresPool(
      endpoint,
      PoolSettings(sslMode: SslMode.require),
    );
  } on Object catch (error) {
    if (!error.toString().contains('does not support SSL')) {
      rethrow;
    }
    stderr.writeln(
      'Postgres server does not support SSL; retrying without encryption.',
    );
    return _openPostgresPool(endpoint, PoolSettings(sslMode: SslMode.disable));
  }
}

Future<Pool<void>> _openPostgresPool(
  Endpoint endpoint,
  PoolSettings settings,
) async {
  final Pool<void> pool = Pool<void>.withEndpoints(<Endpoint>[
    endpoint,
  ], settings: settings);
  try {
    await pool.execute('select 1');
    return pool;
  } on Object {
    await pool.close(force: true);
    rethrow;
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

Handler _appStaticHandler(PostgresChargeRepository repository, String webRoot) {
  final Handler staticHandler = _staticHandler(webRoot);
  return (Request request) async {
    if (request.url.path == 'app') {
      return Response.seeOther('/app/');
    }
    if (!request.url.path.startsWith('app/')) {
      return Response.notFound('');
    }
    if (!await _hasValidSession(repository, request)) {
      return Response.seeOther(
        '/',
        headers: <String, String>{
          'Cache-Control': 'no-store',
          'Set-Cookie': _expiredSessionCookie(request),
        },
      );
    }
    final Response response = await staticHandler(request.change(path: 'app'));
    return response.change(
      headers: <String, String>{
        'Cache-Control': 'no-store',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
    );
  };
}

Router _router(PostgresChargeRepository repository, String webRoot) {
  final Router router = Router();
  const Uuid uuid = Uuid();

  router.get('/api/status', (Request request) async {
    return _json(<String, Object?>{'status': 'ok'});
  });

  router.get('/', (Request request) async {
    final String? sessionId = _sessionIdFromRequest(request);
    final ZaptecSession? session = sessionId == null
        ? null
        : await repository.loadSession(sessionId);
    if (session != null) {
      return Response.seeOther('/app/');
    }
    return _html(await _landingPage(webRoot, request));
  });

  router.get('/login', (Request request) async {
    final String? sessionId = _sessionIdFromRequest(request);
    final ZaptecSession? session = sessionId == null
        ? null
        : await repository.loadSession(sessionId);
    if (session != null) {
      return Response.seeOther('/app/');
    }
    return _html(_loginPage(request));
  });

  router.get('/privacy.html', (Request request) async {
    return _html(await _privacyPage(webRoot, request));
  });

  router.get('/site.css', (Request request) async {
    return Response.ok(
      await _webTextFile(webRoot, 'site.css'),
      headers: const <String, String>{
        'Content-Type': 'text/css; charset=utf-8',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  });

  router.get('/privacy', (Request request) async {
    return Response.seeOther('/privacy.html');
  });

  router.get('/robots.txt', (Request request) async {
    return Response.ok(
      await _robotsText(webRoot, request),
      headers: const <String, String>{
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  });

  router.get('/sitemap.xml', (Request request) async {
    return Response.ok(
      await _sitemapXml(webRoot, request),
      headers: const <String, String>{
        'Content-Type': 'application/xml; charset=utf-8',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  });

  router.get('/sitemap.url', (Request request) async {
    return Response.seeOther('/sitemap.xml');
  });

  router.get('/logout', (Request request) async {
    return Response.seeOther('/');
  });

  router.post('/logout', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final String? sessionId = _sessionIdFromRequest(request);
    if (sessionId != null) {
      await repository.logout(sessionId);
    }
    return Response.seeOther(
      '/',
      headers: <String, String>{
        'Cache-Control': 'no-store',
        'Set-Cookie': _expiredSessionCookie(request),
      },
    );
  });

  router.post(
    '/',
    (Request request) => _handleHtmlLogin(repository, request, uuid.v4()),
  );

  router.post('/login', (Request request) async {
    return _handleHtmlLogin(repository, request, uuid.v4());
  });

  router.get('/api/session', (Request request) async {
    final String? sessionId = _sessionIdFromRequest(request);
    final ZaptecSession? session = sessionId == null
        ? null
        : await repository.loadSession(sessionId);
    return _json(<String, Object?>{'session': _sessionJson(session)});
  });

  router.post('/api/login', (Request request) async {
    final String sessionId = uuid.v4();
    final Map<String, Object?> body = await _readBody(request);
    final String email = body['email']?.toString() ?? '';
    final String password = body['password']?.toString() ?? '';
    if (email.isEmpty || password.isEmpty) {
      return _json(<String, Object?>{
        'error': 'Email and password are required.',
      }, status: 400);
    }
    late final ZaptecSession session;
    try {
      session = await repository.login(email, password, sessionId);
    } on ZaptecException {
      return _json(<String, Object?>{
        'error': 'Invalid Zaptec email or password.',
      }, status: 401);
    }
    return _json(
      <String, Object?>{
        'session': _sessionJson(session, includeAccessToken: true),
      },
      headers: <String, String>{
        'Set-Cookie': _sessionCookie(sessionId, request),
      },
    );
  });

  router.post('/api/logout', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final String? sessionId = _sessionIdFromRequest(request);
    if (sessionId != null) {
      await repository.logout(sessionId);
    }
    return Response.ok(
      jsonEncode(<String, Object?>{'status': 'ok'}),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
        'Set-Cookie': _expiredSessionCookie(request),
      },
    );
  });

  router.post('/api/server-data/delete', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final String? sessionId = _sessionIdFromRequest(request);
    if (sessionId != null) {
      await repository.deleteStoredData(sessionId);
    }
    return Response.ok(
      jsonEncode(<String, Object?>{'status': 'ok'}),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
        'Set-Cookie': _expiredSessionCookie(request),
      },
    );
  });

  router.get('/api/filter', (Request request) async {
    final HistoryFilter? filter = await repository.loadFilter(
      _sessionIdFromRequest(request),
    );
    return _json(<String, Object?>{
      'filter': filter == null ? null : _filterJson(filter),
    });
  });

  router.post('/api/filter', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final String? sessionId = _sessionIdFromRequest(request);
    if (sessionId != null) {
      await repository.saveFilter(
        _filterFromJson(await _readBody(request)),
        sessionId,
      );
    }
    return _json(<String, Object?>{'status': 'ok'});
  });

  router.get('/api/settings', (Request request) async {
    final String? sessionId = _sessionIdFromRequest(request);
    final double? kwhPrice = await repository.loadKwhPrice(sessionId);
    final String? currencyCode = await repository.loadCurrencyCode(sessionId);
    final List<HistoryColumn>? historyColumns = await repository
        .loadHistoryColumns(sessionId);
    return _json(<String, Object?>{
      'kwhPrice': kwhPrice,
      'currencyCode': currencyCode,
      'historyColumns': historyColumns
          ?.map((HistoryColumn column) => column.name)
          .toList(),
    });
  });

  router.post('/api/settings', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final String? sessionId = _sessionIdFromRequest(request);
    if (sessionId != null) {
      final Map<String, Object?> body = await _readBody(request);
      if (body.containsKey('kwhPrice')) {
        await repository.saveKwhPrice(
          (body['kwhPrice'] as num?)?.toDouble(),
          sessionId,
        );
      }
      if (body.containsKey('currencyCode')) {
        await repository.saveCurrencyCode(
          _blankToNull(body['currencyCode']?.toString()),
          sessionId,
        );
      }
      if (body.containsKey('historyColumns')) {
        await repository.saveHistoryColumns(
          _historyColumnsFromJson(body['historyColumns']),
          sessionId,
        );
      }
    }
    return _json(<String, Object?>{'status': 'ok'});
  });

  router.get('/api/chargers', (Request request) async {
    final List<Charger> chargers = await repository.loadChargers(
      _sessionIdFromRequest(request),
    );
    return _json(<String, Object?>{
      'chargers': chargers.map(_chargerJson).toList(),
    });
  });

  router.post('/api/chargers/sync', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final List<Charger> chargers = await repository.syncChargers(
      _sessionIdFromRequest(request),
      _clientAccessTokenFromRequest(request),
    );
    return _json(<String, Object?>{
      'chargers': chargers.map(_chargerJson).toList(),
    });
  });

  router.post('/api/history/sync', (Request request) async {
    final Response? forbidden = _rejectCrossSitePost(request);
    if (forbidden != null) {
      return forbidden;
    }
    final Map<String, Object?> body = await _readBody(request);
    final String? chargerId = _blankToNull(body['chargerId']?.toString());
    final int count = await repository.syncChargeHistory(
      chargerId: chargerId,
      sessionId: _sessionIdFromRequest(request),
      accessToken: _clientAccessTokenFromRequest(request),
    );
    return _json(<String, Object?>{'count': count});
  });

  router.get('/api/history', (Request request) async {
    final HistoryFilter filter = _filterFromQuery(request.url.queryParameters);
    final List<ChargeSession> sessions = await repository.loadChargeHistory(
      filter,
      _sessionIdFromRequest(request),
    );
    return _json(<String, Object?>{
      'sessions': sessions.map(_chargeSessionJson).toList(),
    });
  });

  router.get('/api/history/totals', (Request request) async {
    final HistoryFilter filter = _filterFromQuery(request.url.queryParameters);
    final HistoryTotals totals = await repository.loadHistoryTotals(
      filter,
      _sessionIdFromRequest(request),
    );
    return _json(<String, Object?>{'totals': _totalsJson(totals)});
  });

  router.get('/api/history/period-options', (Request request) async {
    final HistoryFilter filter = _filterFromQuery(request.url.queryParameters);
    final Map<HistoryPeriod, List<String>> options = await repository
        .loadHistoryPeriodOptions(filter, _sessionIdFromRequest(request));
    return _json(<String, Object?>{
      'options': <String, Object?>{
        for (final MapEntry<HistoryPeriod, List<String>> entry
            in options.entries)
          entry.key.name: entry.value,
      },
    });
  });

  return router;
}

Middleware _securityHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      final Response response = await innerHandler(request);
      return response.change(
        headers: <String, String>{
          ...response.headers,
          ..._securityHeaderValues(request),
        },
      );
    };
  };
}

Map<String, String> _securityHeaderValues(Request request) {
  return <String, String>{
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'same-origin',
    'X-Frame-Options': 'DENY',
    'Content-Security-Policy': "frame-ancestors 'none'; base-uri 'self';",
    'Permissions-Policy':
        'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
    if (_externalBaseUri(request).scheme == 'https')
      'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  };
}

Middleware _requireServerSession(PostgresChargeRepository repository) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (!_requiresServerSession(request)) {
        return innerHandler(request);
      }
      if (await _hasValidSession(repository, request)) {
        return innerHandler(request);
      }
      return _json(
        <String, Object?>{'error': 'Login required.'},
        status: 401,
        headers: <String, String>{
          'Cache-Control': 'no-store',
          'Set-Cookie': _expiredSessionCookie(request),
        },
      );
    };
  };
}

bool _requiresServerSession(Request request) {
  if (!request.url.path.startsWith('api/')) {
    return false;
  }
  return !<String>{
    'api/status',
    'api/session',
    'api/login',
    'api/logout',
  }.contains(request.url.path);
}

Future<bool> _hasValidSession(
  PostgresChargeRepository repository,
  Request request,
) async {
  final String? sessionId = _sessionIdFromRequest(request);
  if (sessionId == null) {
    return false;
  }
  return await repository.loadSession(sessionId) != null;
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

Future<Map<String, String>> _readFormBody(Request request) async {
  final String raw = await request.readAsString();
  return Uri.splitQueryString(raw, encoding: utf8);
}

String? _sessionIdFromRequest(Request request) {
  final String? cookieHeader = request.headers['cookie'];
  if (cookieHeader == null || cookieHeader.isEmpty) {
    return null;
  }
  for (final String part in cookieHeader.split(';')) {
    final int separator = part.indexOf('=');
    if (separator < 0) {
      continue;
    }
    final String name = part.substring(0, separator).trim();
    if (name != 'chargeledger_session') {
      continue;
    }
    final String value = Uri.decodeComponent(
      part.substring(separator + 1).trim(),
    );
    return value.isEmpty ? null : value;
  }
  return null;
}

String? _clientAccessTokenFromRequest(Request request) {
  return _blankToNull(request.headers['x-zaptec-access-token']);
}

Response? _rejectCrossSitePost(Request request) {
  final Uri baseUri = _externalBaseUri(request);
  for (final String headerName in <String>['origin', 'referer']) {
    final String? value = request.headers[headerName];
    if (value == null || value.isEmpty) {
      continue;
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        _effectivePort(uri) != _effectivePort(baseUri)) {
      return _json(<String, Object?>{
        'error': 'Cross-site request rejected.',
      }, status: 403);
    }
  }
  return null;
}

Uri _externalBaseUri(Request request) {
  final String? forwardedHost = request.headers['x-forwarded-host']
      ?.split(',')
      .first
      .trim();
  final String scheme =
      request.headers['x-forwarded-proto']?.split(',').first.trim() ??
      request.requestedUri.scheme;
  final String host = forwardedHost ?? request.requestedUri.authority;
  final Uri parsed = Uri.parse('$scheme://$host');
  return parsed;
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return uri.scheme == 'https' ? 443 : 80;
}

String _sessionCookie(String sessionId, Request request) {
  final bool secure = _externalBaseUri(request).scheme == 'https';
  return 'chargeledger_session=${Uri.encodeComponent(sessionId)}; '
      'Path=/; HttpOnly; SameSite=Strict${secure ? '; Secure' : ''}';
}

String _expiredSessionCookie(Request request) {
  final bool secure = _externalBaseUri(request).scheme == 'https';
  return 'chargeledger_session=; Path=/; HttpOnly; SameSite=Strict; '
      'Max-Age=0${secure ? '; Secure' : ''}';
}

Future<Response> _handleHtmlLogin(
  PostgresChargeRepository repository,
  Request request,
  String sessionId,
) async {
  final Map<String, String> body = await _readFormBody(request);
  final String email = body['email']?.trim() ?? '';
  final String password = body['password'] ?? '';
  if (email.isEmpty || password.isEmpty) {
    return _html(
      _loginPage(request, error: 'Email and password are required.'),
      status: 400,
    );
  }
  late final ZaptecSession session;
  try {
    session = await repository.login(email, password, sessionId);
  } on ZaptecException {
    return _html(
      _loginPage(request, error: 'Invalid Zaptec email or password.'),
      status: 401,
    );
  }
  return _html(
    _storeClientSessionPage(session),
    headers: <String, String>{'Set-Cookie': _sessionCookie(sessionId, request)},
  );
}

String _storeClientSessionPage(ZaptecSession session) {
  final String sessionJson = jsonEncode(
    _sessionJson(session, includeAccessToken: true),
  );
  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ChargeLedger Login</title>
</head>
<body>
  <script>
    sessionStorage.setItem('chargeledger.session', ${jsonEncode(sessionJson)});
    window.location.replace('/app/');
  </script>
  <noscript>JavaScript is required to open ChargeLedger.</noscript>
</body>
</html>
''';
}

Future<String> _landingPage(String webRoot, Request request) {
  final String canonical = _absoluteUrl(request, '/');
  final String privacyUrl = _absoluteUrl(request, '/privacy.html');
  final String loginUrl = _absoluteUrl(request, '/login');
  final String structuredData = jsonEncode(<String, Object?>{
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    'name': 'ChargeLedger',
    'applicationCategory': 'BusinessApplication',
    'operatingSystem': 'Web, Android, iOS, macOS, Windows, Linux',
    'description':
        'ChargeLedger gives Zaptec users deeper charging insight than the provider interface offers by adding filters, totals, history review, and cost calculations.',
    'url': canonical,
    'codeRepository': 'https://github.com/ronaldderksen/chargeledger',
    'offers': <String, Object?>{
      '@type': 'Offer',
      'price': '0',
      'priceCurrency': 'EUR',
    },
  });
  return _renderWebTemplate(webRoot, 'landing.html', <String, String>{
    'canonicalUrl': canonical,
    'privacyUrl': privacyUrl,
    'loginUrl': loginUrl,
    'structuredData': structuredData,
  });
}

Future<String> _privacyPage(String webRoot, Request request) {
  final String canonical = _absoluteUrl(request, '/privacy.html');
  final String homeUrl = _absoluteUrl(request, '/');
  return _renderWebTemplate(webRoot, 'privacy.html', <String, String>{
    'canonicalUrl': canonical,
    'homeUrl': homeUrl,
  });
}

Future<String> _robotsText(String webRoot, Request request) {
  return _renderWebTemplate(webRoot, 'robots.txt', <String, String>{
    'sitemapUrl': _absoluteUrl(request, '/sitemap.xml'),
  });
}

Future<String> _sitemapXml(String webRoot, Request request) {
  return _renderWebTemplate(webRoot, 'sitemap.xml', <String, String>{
    'homeUrl': _absoluteUrl(request, '/'),
    'privacyUrl': _absoluteUrl(request, '/privacy.html'),
  });
}

String _absoluteUrl(Request request, String path) {
  final Uri baseUri = _externalBaseUri(request);
  return baseUri.replace(path: path, query: '').toString();
}

Future<String> _renderWebTemplate(
  String webRoot,
  String fileName,
  Map<String, String> replacements,
) async {
  String content = await _webTextFile(webRoot, fileName);
  for (final MapEntry<String, String> replacement in replacements.entries) {
    content = content.replaceAll('{{${replacement.key}}}', replacement.value);
  }
  return content;
}

Future<String> _webTextFile(String webRoot, String fileName) async {
  final List<File> candidates = <File>[
    File('${_stripTrailingSlash(webRoot)}/$fileName'),
    File('web/$fileName'),
    File('/app/web/$fileName'),
  ];
  for (final File file in candidates) {
    if (await file.exists()) {
      return file.readAsString();
    }
  }
  throw StateError('Web file not found: $fileName');
}

String _stripTrailingSlash(String value) {
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String _loginPage(Request request, {String? error}) {
  final String canonical = _absoluteUrl(request, '/login');
  final String errorHtml = error == null
      ? ''
      : '<div class="error">${_htmlEscape(error)}</div>';
  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ChargeLedger Login</title>
  <meta name="robots" content="noindex,nofollow">
  <link rel="canonical" href="$canonical">
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: flex-start;
      justify-content: center;
      background: #f6f8f7;
      color: #17201b;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 18px 20px 28px;
      box-sizing: border-box;
    }
    form {
      width: min(440px, 100%);
      margin-top: 0;
      padding: 20px;
      background: #fff;
      border: 1px solid #d7ded9;
      border-radius: 8px;
      box-sizing: border-box;
    }
    h1 {
      margin: 0 0 16px;
      font-size: 22px;
      line-height: 1.25;
      font-weight: 400;
    }
    label {
      display: block;
      margin: 10px 0 6px;
      font-size: 12px;
      font-weight: 400;
      color: #3f4944;
    }
    input,
    select {
      width: 100%;
      min-height: 48px;
      padding: 10px 12px;
      border: 1px solid #d7ded9;
      border-radius: 8px;
      box-sizing: border-box;
      font: inherit;
      background: #fff;
      outline-color: #24745b;
    }
    button {
      width: 100%;
      margin-top: 16px;
      min-height: 40px;
      padding: 10px 16px;
      border: 0;
      border-radius: 20px;
      background: #24745b;
      color: white;
      font: inherit;
      font-weight: 500;
      cursor: pointer;
    }
    .error {
      margin-bottom: 14px;
      padding: 12px;
      border-radius: 8px;
      background: #ffdad6;
      color: #410002;
    }
  </style>
</head>
<body>
  <form method="post" action="/login" autocomplete="on">
    <h1>Zaptec login</h1>
    $errorHtml
    <label for="chargerType">Charger type</label>
    <select id="chargerType" name="chargerType">
      <option value="zaptec" selected>Zaptec</option>
    </select>
    <label for="email">Email</label>
    <input
      id="email"
      name="email"
      type="email"
      autocomplete="username email"
      inputmode="email"
      required
      autofocus>
    <label for="password">Password</label>
    <input
      id="password"
      name="password"
      type="password"
      autocomplete="current-password"
      required>
    <button type="submit">Log in</button>
  </form>
</body>
</html>
''';
}

String _htmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
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
    startDate: _parseDate(json['startDate']?.toString()),
    endDate: _parseDate(json['endDate']?.toString()),
    chargerId: _blankToNull(json['chargerId']?.toString()),
  );
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

List<HistoryColumn> _historyColumnsFromJson(Object? value) {
  if (value is! List) {
    return const <HistoryColumn>[];
  }
  return value
      .map(
        (Object? name) => HistoryColumn.values
            .where((HistoryColumn column) => column.name == name)
            .firstOrNull,
      )
      .whereType<HistoryColumn>()
      .toList();
}

Response _json(
  Map<String, Object?> body, {
  int status = 200,
  Map<String, String>? headers,
}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      ...?headers,
    },
  );
}

Response _html(String body, {int status = 200, Map<String, String>? headers}) {
  return Response(
    status,
    body: body,
    headers: <String, String>{
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      ...?headers,
    },
  );
}

Map<String, Object?>? _sessionJson(
  ZaptecSession? session, {
  bool includeAccessToken = false,
}) {
  if (session == null) {
    return null;
  }
  return <String, Object?>{
    'customerId': session.customerId,
    'email': session.email,
    'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    if (includeAccessToken) 'accessToken': session.accessToken,
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
