import 'package:postgres/postgres.dart';

import 'schema_definitions.dart';

Future<void> checkPostgresDatabase(Session conn) async {
  for (final MapEntry<String, TableSpec> entry in tableDefinitions.entries) {
    await _ensureTable(conn, entry.key, entry.value);
  }
}

Future<void> _ensureTable(
  Session conn,
  String tableName,
  TableSpec tableSpec,
) async {
  final Map<String, ColumnSpec> columns = Map<String, ColumnSpec>.from(
    tableSpec['columns'] as Map,
  );
  final List<String> primaryKey = List<String>.from(
    tableSpec['primaryKey'] as List,
  );
  await _ensureSequences(conn, columns);
  if (!await _tableExists(conn, tableName)) {
    await _createTable(conn, tableName, columns, primaryKey);
  }
  final Map<String, Map<String, Object?>> actualColumns = await _loadColumns(
    conn,
    tableName,
  );
  for (final MapEntry<String, ColumnSpec> column in columns.entries) {
    await _ensureColumn(
      conn,
      tableName,
      column.key,
      column.value,
      actualColumns[column.key],
    );
  }
  await _dropRemovedColumns(conn, tableName, columns, actualColumns);
  await _ensurePrimaryKey(conn, tableName, primaryKey);
  await _ensureIndexes(conn, tableName, tableSpec);
}

Future<void> _ensureSequences(
  Session conn,
  Map<String, ColumnSpec> columns,
) async {
  for (final ColumnSpec column in columns.values) {
    final String? sequenceName = column['sequence'] as String?;
    if (sequenceName != null && !await _sequenceExists(conn, sequenceName)) {
      await conn.execute('CREATE SEQUENCE public.${_quote(sequenceName)}');
    }
  }
}

Future<bool> _tableExists(Session conn, String tableName) async {
  final Result result = await conn.execute(
    Sql.named(
      'select 1 from information_schema.tables '
      'where table_schema = @schema and table_name = @table limit 1',
    ),
    parameters: <String, Object?>{'schema': 'public', 'table': tableName},
  );
  return result.isNotEmpty;
}

Future<Map<String, Map<String, Object?>>> _loadColumns(
  Session conn,
  String tableName,
) async {
  final Result result = await conn.execute(
    Sql.named(
      'select column_name, data_type, is_nullable, column_default '
      'from information_schema.columns '
      'where table_schema = @schema and table_name = @table',
    ),
    parameters: <String, Object?>{'schema': 'public', 'table': tableName},
  );
  return <String, Map<String, Object?>>{
    for (final ResultRow row in result)
      row[0] as String: <String, Object?>{
        'type': (row[1] as String).toLowerCase(),
        'isNullable': row[2] as String,
        'default': row[3] as String?,
      },
  };
}

Future<void> _createTable(
  Session conn,
  String tableName,
  Map<String, ColumnSpec> columns,
  List<String> primaryKey,
) async {
  final List<String> definitions = <String>[
    for (final MapEntry<String, ColumnSpec> column in columns.entries)
      _columnDefinition(column.key, column.value),
  ];
  if (primaryKey.isNotEmpty) {
    definitions.add('PRIMARY KEY (${primaryKey.map(_quote).join(', ')})');
  }
  await conn.execute(
    'CREATE TABLE IF NOT EXISTS public.${_quote(tableName)} '
    '(${definitions.join(', ')})',
  );
}

Future<void> _ensureColumn(
  Session conn,
  String tableName,
  String columnName,
  ColumnSpec expected,
  Map<String, Object?>? actual,
) async {
  if (actual == null) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ADD COLUMN '
      '${_columnDefinition(columnName, expected)}',
    );
    return;
  }
  final String expectedType = (expected['type'] as String).toLowerCase();
  final String actualType = (actual['type'] as String).toLowerCase();
  if (actualType != expectedType) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ALTER COLUMN '
      '${_quote(columnName)} TYPE $expectedType',
    );
  }
  final bool expectedNotNull = expected['notNull'] as bool? ?? false;
  final bool isNullable =
      (actual['isNullable'] as String).toUpperCase() == 'YES';
  if (expectedNotNull && isNullable) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ALTER COLUMN '
      '${_quote(columnName)} SET NOT NULL',
    );
  } else if (!expectedNotNull && !isNullable) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ALTER COLUMN '
      '${_quote(columnName)} DROP NOT NULL',
    );
  }
  final String? actualDefault = _normalizeDefault(actual['default'] as String?);
  final String? expectedDefault = _normalizeDefault(
    expected['default'] as String?,
  );
  if (actualDefault == expectedDefault) {
    return;
  }
  if (expectedDefault == null) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ALTER COLUMN '
      '${_quote(columnName)} DROP DEFAULT',
    );
  } else {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} ALTER COLUMN '
      '${_quote(columnName)} SET DEFAULT $expectedDefault',
    );
  }
}

Future<void> _dropRemovedColumns(
  Session conn,
  String tableName,
  Map<String, ColumnSpec> expectedColumns,
  Map<String, Map<String, Object?>> actualColumns,
) async {
  for (final String columnName in actualColumns.keys) {
    if (!expectedColumns.containsKey(columnName)) {
      await conn.execute(
        'ALTER TABLE public.${_quote(tableName)} DROP COLUMN ${_quote(columnName)}',
      );
    }
  }
}

Future<void> _ensurePrimaryKey(
  Session conn,
  String tableName,
  List<String> expectedPrimaryKey,
) async {
  final Result result = await conn.execute(
    Sql.named(
      'select tc.constraint_name, kcu.column_name '
      'from information_schema.table_constraints tc '
      'join information_schema.key_column_usage kcu '
      'on tc.constraint_name = kcu.constraint_name '
      'and tc.table_schema = kcu.table_schema '
      'where tc.table_schema = @schema and tc.table_name = @table '
      "and tc.constraint_type = 'PRIMARY KEY' "
      'order by kcu.ordinal_position',
    ),
    parameters: <String, Object?>{'schema': 'public', 'table': tableName},
  );
  final List<String> existingColumns = <String>[];
  String? constraintName;
  for (final ResultRow row in result) {
    constraintName ??= row[0] as String?;
    final String? columnName = row[1] as String?;
    if (columnName != null) {
      existingColumns.add(columnName);
    }
  }
  if (constraintName == null && expectedPrimaryKey.isNotEmpty) {
    await _addPrimaryKey(conn, tableName, expectedPrimaryKey);
    return;
  }
  if (constraintName != null &&
      !_listEquals(existingColumns, expectedPrimaryKey)) {
    await conn.execute(
      'ALTER TABLE public.${_quote(tableName)} DROP CONSTRAINT '
      '${_quote(constraintName)}',
    );
    if (expectedPrimaryKey.isNotEmpty) {
      await _addPrimaryKey(conn, tableName, expectedPrimaryKey);
    }
  }
}

Future<void> _addPrimaryKey(
  Session conn,
  String tableName,
  List<String> primaryKey,
) async {
  await conn.execute(
    'ALTER TABLE public.${_quote(tableName)} ADD PRIMARY KEY '
    '(${primaryKey.map(_quote).join(', ')})',
  );
}

Future<void> _ensureIndexes(
  Session conn,
  String tableName,
  TableSpec tableSpec,
) async {
  final Map<String, IndexSpec> indexes = Map<String, IndexSpec>.from(
    (tableSpec['indexes'] as Map?) ?? const {},
  );
  for (final MapEntry<String, IndexSpec> index in indexes.entries) {
    final List<String> columns = List<String>.from(
      index.value['columns'] as List,
    );
    final bool unique = index.value['unique'] as bool? ?? false;
    final String method = index.value['method'] as String? ?? 'btree';
    await conn.execute(
      'CREATE ${unique ? 'UNIQUE ' : ''}INDEX IF NOT EXISTS ${_quote(index.key)} '
      'ON public.${_quote(tableName)} USING $method '
      '(${columns.map(_quote).join(', ')})',
    );
  }
}

String _columnDefinition(String columnName, ColumnSpec spec) {
  final StringBuffer buffer = StringBuffer(
    '${_quote(columnName)} ${spec['type'] as String}',
  );
  final String? defaultValue = spec['default'] as String?;
  final String? references = spec['references'] as String?;
  if (defaultValue != null) {
    buffer.write(' DEFAULT $defaultValue');
  }
  if (spec['notNull'] as bool? ?? false) {
    buffer.write(' NOT NULL');
  }
  if (references != null) {
    buffer.write(' REFERENCES public.$references ON DELETE CASCADE');
  }
  return buffer.toString();
}

Future<bool> _sequenceExists(Session conn, String sequenceName) async {
  final Result result = await conn.execute(
    Sql.named(
      'select 1 from pg_class where relname = @sequence '
      "and relkind = 'S' limit 1",
    ),
    parameters: <String, Object?>{'sequence': sequenceName},
  );
  return result.isNotEmpty;
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

String? _normalizeDefault(String? value) {
  if (value == null) {
    return null;
  }
  String normalized = value.trim();
  if (normalized.startsWith('nextval(')) {
    return normalized.replaceAll('public.', '');
  }
  normalized = normalized.replaceAll(RegExp(r'::[\w\s]+'), '');
  normalized = normalized.replaceAll("'", '');
  return normalized;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
