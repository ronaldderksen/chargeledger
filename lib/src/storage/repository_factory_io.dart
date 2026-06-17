import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'charge_repository.dart';
import 'sqlite_charge_repository.dart';

Future<ChargeRepository> createPlatformRepository() async {
  final directory = await getApplicationDocumentsDirectory();
  final Database db = sqlite3.open(
    p.join(directory.path, 'chargeledger.sqlite'),
  );
  return SqliteChargeRepository(database: db);
}
