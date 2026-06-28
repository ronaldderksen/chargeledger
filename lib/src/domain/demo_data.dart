import 'models.dart';

const String demoAccountName = 'demo';
const String demoAccountPassword = 'demo';
const String demoAccessToken = 'demo-access-token';

bool isDemoLogin(String account, String password) {
  final String normalizedPassword = password.trim().toLowerCase();
  return isDemoAccount(account) &&
      (normalizedPassword.isEmpty || normalizedPassword == demoAccountPassword);
}

bool isDemoAccount(String account) {
  return account.trim().toLowerCase() == demoAccountName;
}

bool isDemoSession(ZaptecSession session) {
  return isDemoAccount(session.email) || session.accessToken == demoAccessToken;
}

ZaptecSession demoSession({required String customerId}) {
  return ZaptecSession(
    customerId: customerId,
    email: demoAccountName,
    accessToken: demoAccessToken,
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
  );
}

List<Charger> demoChargers() {
  return const <Charger>[
    Charger(
      id: 'demo-home',
      name: 'Home',
      serialNumber: 'DEMO-001',
      installationId: 'demo-installation',
    ),
  ];
}

List<ChargeSession> demoChargeSessions({String? chargerId}) {
  final Charger charger = demoChargers().first;
  final String activeChargerId = chargerId?.trim().isNotEmpty == true
      ? chargerId!.trim()
      : charger.id;
  final String chargerName = activeChargerId == charger.id
      ? charger.name
      : 'Demo charger';
  final DateTime now = DateTime.now().toUtc();
  return List<ChargeSession>.generate(100, (int index) {
    final int daysBack = (index * 365 / 99).round();
    final int startHour = 5 + (index * 7) % 18;
    final int startMinute = (index * 13) % 60;
    final DateTime startTime = DateTime.utc(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    ).subtract(Duration(days: daysBack));
    final int durationMinutes = 42 + (index * 17) % 620;
    final DateTime endTime = startTime.add(Duration(minutes: durationMinutes));
    final double energyKwh =
        (650 + (index * 137) % 5200 + (index % 4) * 25) / 100;
    return ChargeSession(
      id: 'demo-session-${index.toString().padLeft(3, '0')}',
      chargerId: activeChargerId,
      chargerName: chargerName,
      userName: index % 5 == 0 ? 'Guest' : 'Demo user',
      startTime: startTime,
      endTime: endTime,
      energyKwh: energyKwh,
      durationSeconds: durationMinutes * 60,
    );
  });
}
