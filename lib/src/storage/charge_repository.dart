import '../domain/models.dart';

abstract class ChargeRepository {
  Future<void> initialize();
  Future<ZaptecSession?> loadSession();
  Future<ZaptecSession> login(String email, String password);
  Future<void> logout();
  Future<List<Charger>> syncChargers();
  Future<List<Charger>> loadChargers();
  Future<int> syncChargeHistory({String? chargerId});
  Future<List<ChargeSession>> loadChargeHistory(HistoryFilter filter);
  Future<HistoryTotals> loadHistoryTotals(HistoryFilter filter);
}
