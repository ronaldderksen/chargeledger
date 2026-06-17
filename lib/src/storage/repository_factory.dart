import 'charge_repository.dart';
import 'repository_factory_stub.dart'
    if (dart.library.io) 'repository_factory_io.dart'
    if (dart.library.js_interop) 'repository_factory_web.dart';

Future<ChargeRepository> createRepository() => createPlatformRepository();
