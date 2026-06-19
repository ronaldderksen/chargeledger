import '../domain/models.dart';

class LoginRequiredException implements Exception {
  const LoginRequiredException();
}

abstract class ChargeRepository {
  Future<void> initialize();
  Future<ZaptecSession?> loadSession();
  Future<ZaptecSession> login(String email, String password);
  Future<void> logout();
  Future<void> deleteStoredData();
  Future<HistoryFilter?> loadFilter();
  Future<void> saveFilter(HistoryFilter filter);
  Future<double?> loadKwhPrice();
  Future<void> saveKwhPrice(double? price);
  Future<String?> loadCurrencyCode();
  Future<void> saveCurrencyCode(String? currencyCode);
  Future<List<HistoryColumn>?> loadHistoryColumns();
  Future<void> saveHistoryColumns(List<HistoryColumn> columns);
  Future<List<Charger>> syncChargers();
  Future<List<Charger>> loadChargers();
  Future<int> syncChargeHistory({String? chargerId});
  Future<List<ChargeSession>> loadChargeHistory(HistoryFilter filter);
  Future<HistoryTotals> loadHistoryTotals(HistoryFilter filter);
  Future<Map<HistoryPeriod, List<String>>> loadHistoryPeriodOptions(
    HistoryFilter filter,
  );
}
