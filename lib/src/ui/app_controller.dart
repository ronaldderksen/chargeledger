import 'package:flutter/foundation.dart';

import '../domain/history_periods.dart';
import '../domain/models.dart';
import '../storage/charge_repository.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository);

  final ChargeRepository _repository;

  bool isLoading = true;
  bool isBusy = false;
  String? message;
  String? error;
  ZaptecSession? session;
  List<Charger> chargers = const <Charger>[];
  List<ChargeSession> sessions = const <ChargeSession>[];
  HistoryTotals totals = HistoryTotals.empty;
  HistoryFilter filter = HistoryFilter(
    periodValue: defaultPeriodValue(HistoryPeriod.all),
  );
  int _historyRefreshId = 0;

  Future<void> initialize() async {
    await _run(() async {
      await _repository.initialize();
      session = await _repository.loadSession();
      chargers = await _repository.loadChargers();
      _ensureSelectedCharger();
      await refreshHistory();
    }, initial: true);
  }

  Future<void> login(String email, String password) async {
    await _run(() async {
      session = await _repository.login(email, password);
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      message = 'Logged in as ${session!.email}.';
      await refreshHistory();
    });
  }

  Future<void> logout() async {
    await _run(() async {
      await _repository.logout();
      session = null;
      chargers = const <Charger>[];
      sessions = const <ChargeSession>[];
      totals = HistoryTotals.empty;
      message = 'Logged out.';
    });
  }

  Future<void> syncChargers() async {
    await _run(() async {
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      message = '${chargers.length} chargers updated.';
      await refreshHistory();
    });
  }

  Future<void> syncHistory() async {
    await _run(() async {
      _ensureSelectedCharger();
      if (filter.chargerId == null) {
        throw StateError('No charger is available.');
      }
      final int count = await _repository.syncChargeHistory(
        chargerId: filter.chargerId,
      );
      message = '$count sessions fetched.';
      await refreshHistory();
    });
  }

  Future<void> setFilter(HistoryFilter value) async {
    filter = value;
    _ensureSelectedCharger();
    notifyListeners();
    await refreshHistory();
  }

  Future<void> shiftPeriod(int step) async {
    final String current = filter.periodValue?.isNotEmpty == true
        ? filter.periodValue!
        : defaultPeriodValue(filter.period);
    await setFilter(
      filter.copyWith(
        periodValue: shiftPeriodValue(filter.period, current, step),
      ),
    );
  }

  Future<void> refreshHistory() async {
    _ensureSelectedCharger();
    final int refreshId = ++_historyRefreshId;
    final HistoryFilter activeFilter = filter;
    final List<ChargeSession> loadedSessions = await _repository
        .loadChargeHistory(activeFilter);
    final HistoryTotals loadedTotals = await _repository.loadHistoryTotals(
      activeFilter,
    );
    if (refreshId != _historyRefreshId || filter != activeFilter) {
      return;
    }
    sessions = loadedSessions;
    totals = loadedTotals;
    notifyListeners();
  }

  void _ensureSelectedCharger() {
    if (chargers.isEmpty) {
      filter = filter.copyWith(clearCharger: true);
      return;
    }
    final bool selectedExists = chargers.any(
      (Charger charger) => charger.id == filter.chargerId,
    );
    if (!selectedExists) {
      filter = filter.copyWith(chargerId: chargers.first.id);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool initial = false,
  }) async {
    error = null;
    if (initial) {
      isLoading = true;
    } else {
      isBusy = true;
    }
    notifyListeners();
    try {
      await action();
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      isLoading = false;
      isBusy = false;
      notifyListeners();
    }
  }
}
