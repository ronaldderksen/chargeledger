import 'package:sqlite3/sqlite3.dart';

import 'schema_definitions.dart';

void checkSqliteDatabase(Database db) {
  db.execute('PRAGMA foreign_keys = ON');
  for (final MapEntry<String, TableSpec> tableEntry
      in tableDefinitions.entries) {
    _ensureTable(db, tableEntry.key, tableEntry.value);
  }
}

void _ensureTable(Database db, String tableName, TableSpec tableSpec) {
  final Map<String, ColumnSpec> columns = Map<String, ColumnSpec>.from(
    tableSpec['columns'] as Map,
  );
  final List<String> primaryKey = List<String>.from(
    tableSpec['primaryKey'] as List,
  );
  final List<String> definitions = <String>[];

  for (final MapEntry<String, ColumnSpec> entry in columns.entries) {
    definitions.add(_columnDefinition(entry.key, entry.value));
  }
  if (primaryKey.isNotEmpty) {
    definitions.add('PRIMARY KEY (${primaryKey.map(_quote).join(', ')})');
  }

  db.execute(
    'CREATE TABLE IF NOT EXISTS ${_quote(tableName)} '
    '(${definitions.join(', ')})',
  );

  final ResultSet existing = db.select(
    'PRAGMA table_info(${_quote(tableName)})',
  );
  final Set<String> existingColumns = existing
      .map((Row row) => row['name'] as String)
      .toSet();
  for (final MapEntry<String, ColumnSpec> entry in columns.entries) {
    if (!existingColumns.contains(entry.key)) {
      db.execute(
        'ALTER TABLE ${_quote(tableName)} ADD COLUMN '
        '${_columnDefinition(entry.key, entry.value)}',
      );
    }
  }
  _ensureIndexes(db, tableName, tableSpec);
}

String _columnDefinition(String columnName, ColumnSpec spec) {
  final String type = spec['sqliteType'] as String? ?? 'text';
  final bool notNull = spec['notNull'] as bool? ?? false;
  final String? defaultValue = spec['sqliteDefault'] as String?;
  final StringBuffer buffer = StringBuffer('${_quote(columnName)} $type');
  if (notNull) {
    buffer.write(' NOT NULL');
  }
  if (defaultValue != null) {
    buffer.write(' DEFAULT $defaultValue');
  }
  return buffer.toString();
}

void _ensureIndexes(Database db, String tableName, TableSpec tableSpec) {
  final Map<String, IndexSpec> indexes = Map<String, IndexSpec>.from(
    (tableSpec['indexes'] as Map?) ?? const {},
  );
  for (final MapEntry<String, IndexSpec> entry in indexes.entries) {
    final List<String> columns = List<String>.from(
      entry.value['columns'] as List,
    );
    final bool unique = entry.value['unique'] as bool? ?? false;
    db.execute(
      'CREATE ${unique ? 'UNIQUE ' : ''}INDEX IF NOT EXISTS ${_quote(entry.key)} '
      'ON ${_quote(tableName)} (${columns.map(_quote).join(', ')})',
    );
  }
}

String _quote(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}
