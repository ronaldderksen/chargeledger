import 'charge_repository.dart';
import 'http_charge_repository.dart';

Future<ChargeRepository> createPlatformRepository() async {
  return HttpChargeRepository();
}
