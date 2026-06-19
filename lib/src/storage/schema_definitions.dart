typedef ColumnSpec = Map<String, Object?>;
typedef IndexSpec = Map<String, Object?>;
typedef TableSpec = Map<String, Object?>;

const Map<String, TableSpec> tableDefinitions = <String, TableSpec>{
  'customers': <String, Object?>{
    'columns': <String, ColumnSpec>{
      'id': <String, Object?>{
        'type': 'uuid',
        'sqliteType': 'text',
        'notNull': true,
      },
      'email': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'created_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
      'updated_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
    },
    'primaryKey': <String>['id'],
    'indexes': <String, IndexSpec>{
      'customers_email_key': <String, Object?>{
        'columns': <String>['email'],
        'unique': true,
      },
    },
  },
  'schema_state': <String, Object?>{
    'columns': <String, ColumnSpec>{
      'key': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'value': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'updated_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
    },
    'primaryKey': <String>['key'],
  },
  'zaptec_chargers': <String, Object?>{
    'columns': <String, ColumnSpec>{
      'customer_id': <String, Object?>{
        'type': 'uuid',
        'sqliteType': 'text',
        'notNull': true,
        'references': 'customers(id)',
      },
      'id': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'name': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'serial_number': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'installation_id': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'created_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
      'updated_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
    },
    'primaryKey': <String>['customer_id', 'id'],
    'indexes': <String, IndexSpec>{
      'zaptec_chargers_installation_id_idx': <String, Object?>{
        'columns': <String>['customer_id', 'installation_id'],
      },
      'zaptec_chargers_serial_number_key': <String, Object?>{
        'columns': <String>['customer_id', 'serial_number'],
        'unique': true,
      },
    },
  },
  'charger_measurements': <String, Object?>{
    'columns': <String, ColumnSpec>{
      'customer_id': <String, Object?>{
        'type': 'uuid',
        'sqliteType': 'text',
        'notNull': true,
        'references': 'customers(id)',
      },
      'id': <String, Object?>{
        'type': 'bigint',
        'sqliteType': 'integer',
        'notNull': true,
        'default': "nextval('charger_measurements_id_seq'::regclass)",
        'sequence': 'charger_measurements_id_seq',
      },
      'charger_id': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'measured_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
      },
      'metric': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'value': <String, Object?>{
        'type': 'double precision',
        'sqliteType': 'real',
        'notNull': true,
      },
      'unit': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'created_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
    },
    'primaryKey': <String>['customer_id', 'id'],
    'indexes': <String, IndexSpec>{
      'charger_measurements_charger_id_measured_at_idx': <String, Object?>{
        'columns': <String>['customer_id', 'charger_id', 'measured_at'],
      },
      'charger_measurements_metric_idx': <String, Object?>{
        'columns': <String>['customer_id', 'metric'],
      },
    },
  },
  'charge_history': <String, Object?>{
    'columns': <String, ColumnSpec>{
      'customer_id': <String, Object?>{
        'type': 'uuid',
        'sqliteType': 'text',
        'notNull': true,
        'references': 'customers(id)',
      },
      'id': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': true,
      },
      'charger_id': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'user_name': <String, Object?>{
        'type': 'text',
        'sqliteType': 'text',
        'notNull': false,
      },
      'start_time': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': false,
      },
      'end_time': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': false,
      },
      'energy_kwh': <String, Object?>{
        'type': 'double precision',
        'sqliteType': 'real',
        'notNull': false,
      },
      'duration_seconds': <String, Object?>{
        'type': 'integer',
        'sqliteType': 'integer',
        'notNull': false,
      },
      'cost': <String, Object?>{
        'type': 'double precision',
        'sqliteType': 'real',
        'notNull': false,
      },
      'created_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
      'updated_at': <String, Object?>{
        'type': 'timestamp without time zone',
        'sqliteType': 'text',
        'notNull': true,
        'default': 'now()',
        'sqliteDefault': "CURRENT_TIMESTAMP",
      },
    },
    'primaryKey': <String>['customer_id', 'id'],
    'indexes': <String, IndexSpec>{
      'charge_history_charger_id_idx': <String, Object?>{
        'columns': <String>['customer_id', 'charger_id'],
      },
      'charge_history_start_time_idx': <String, Object?>{
        'columns': <String>['customer_id', 'start_time'],
      },
      'charge_history_end_time_idx': <String, Object?>{
        'columns': <String>['customer_id', 'end_time'],
      },
    },
  },
};
