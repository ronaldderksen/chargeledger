import 'charge_repository.dart';

Future<ChargeRepository> createPlatformRepository() {
  throw UnsupportedError('No storage backend is available for this platform.');
}
