import 'package:flutter/foundation.dart';

import '../domain/history_periods.dart';
import '../domain/models.dart';
import '../storage/charge_repository.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository);

  final ChargeRepository _repository;

  bool isLoading = true;
  bool isBusy = false;
  bool isSyncingHistory = false;
  String? message;
  String? error;
  ZaptecSession? session;
  List<Charger> chargers = const <Charger>[];
  List<ChargeSession> sessions = const <ChargeSession>[];
  HistoryTotals totals = HistoryTotals.empty;
  Map<HistoryPeriod, List<String>> historyPeriodOptions =
      _emptyHistoryPeriodOptions();
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
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      await refreshHistory();
    }, initial: true);
  }

  Future<void> login(String email, String password) async {
    await _run(() async {
      session = await _repository.login(email, password);
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
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
      historyPeriodOptions = _emptyHistoryPeriodOptions();
      message = 'Logged out.';
    });
  }

  Future<void> syncChargers() async {
    await _run(() async {
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      message = '${chargers.length} chargers updated.';
      await refreshHistory();
    });
  }

  Future<void> syncAll() async {
    await _run(() async {
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      if (filter.chargerId == null) {
        throw StateError('No charger is available.');
      }
      final int count = await _repository.syncChargeHistory(
        chargerId: filter.chargerId,
      );
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      message = '${chargers.length} chargers updated, $count sessions fetched.';
      await refreshHistory();
    }, syncingHistory: true);
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
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      await refreshHistory();
    }, syncingHistory: true);
  }

  Future<void> setFilter(HistoryFilter value) async {
    filter = value;
    _ensureSelectedCharger();
    await refreshHistoryPeriodOptions();
    _ensureSelectedPeriodValue();
    notifyListeners();
    await refreshHistory();
  }

  Future<void> shiftPeriod(int step) async {
    final List<String> options = periodOptionsFor(filter.period);
    final String current = _selectedPeriodValue(filter.period);
    if (options.isNotEmpty) {
      final int currentIndex = options.indexOf(current);
      final int nextIndex = currentIndex + step;
      if (currentIndex < 0 || nextIndex < 0 || nextIndex >= options.length) {
        return;
      }
      await setFilter(filter.copyWith(periodValue: options[nextIndex]));
      return;
    }
    await setFilter(
      filter.copyWith(
        periodValue: shiftPeriodValue(filter.period, current, step),
      ),
    );
  }

  Future<void> refreshHistoryPeriodOptions() async {
    historyPeriodOptions = await _repository.loadHistoryPeriodOptions(filter);
  }

  List<String> periodOptionsFor(HistoryPeriod period) {
    return historyPeriodOptions[period] ?? const <String>[];
  }

  bool canShiftPeriod(int step) {
    final List<String> options = periodOptionsFor(filter.period);
    if (options.isEmpty) {
      return false;
    }
    final int currentIndex = options.indexOf(
      _selectedPeriodValue(filter.period),
    );
    final int nextIndex = currentIndex + step;
    return currentIndex >= 0 && nextIndex >= 0 && nextIndex < options.length;
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

  void _ensureSelectedPeriodValue() {
    if (filter.period == HistoryPeriod.all ||
        filter.period == HistoryPeriod.custom) {
      return;
    }
    final List<String> options = periodOptionsFor(filter.period);
    if (options.isEmpty) {
      return;
    }
    final String current = _selectedPeriodValue(filter.period);
    if (!options.contains(current)) {
      filter = filter.copyWith(periodValue: options.first);
    }
  }

  String _selectedPeriodValue(HistoryPeriod period) {
    return filter.periodValue?.isNotEmpty == true
        ? filter.periodValue!
        : defaultPeriodValue(period);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool initial = false,
    bool syncingHistory = false,
  }) async {
    error = null;
    if (initial) {
      isLoading = true;
    } else {
      isBusy = true;
    }
    isSyncingHistory = syncingHistory;
    notifyListeners();
    try {
      await action();
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      isLoading = false;
      isBusy = false;
      isSyncingHistory = false;
      notifyListeners();
    }
  }
}

Map<HistoryPeriod, List<String>> _emptyHistoryPeriodOptions() {
  return <HistoryPeriod, List<String>>{
    HistoryPeriod.year: <String>[],
    HistoryPeriod.quarter: <String>[],
    HistoryPeriod.month: <String>[],
    HistoryPeriod.week: <String>[],
  };
}
