import 'package:flutter/foundation.dart';

import '../analytics/app_analytics.dart';
import '../domain/demo_data.dart';
import '../domain/history_periods.dart';
import '../domain/models.dart';
import '../storage/charge_repository.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository, {AppAnalytics? analytics})
    : _analytics = analytics;

  final ChargeRepository _repository;
  final AppAnalytics? _analytics;

  bool isLoading = true;
  bool isBusy = false;
  bool isSyncingHistory = false;
  String? message;
  String? error;
  ZaptecSession? session;
  double? kwhPrice;
  String currencyCode = 'EUR';
  List<Charger> chargers = const <Charger>[];
  List<ChargeSession> sessions = const <ChargeSession>[];
  List<HistoryColumn> historyColumns = HistoryColumn.values;
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
      filter = await _repository.loadFilter() ?? filter;
      kwhPrice = await _repository.loadKwhPrice();
      currencyCode = await _repository.loadCurrencyCode() ?? currencyCode;
      historyColumns =
          await _repository.loadHistoryColumns() ?? HistoryColumn.values;
      chargers = await _repository.loadChargers();
      _ensureSelectedCharger();
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      await _saveFilter();
      await refreshHistory();
    }, initial: true);
  }

  Future<void> login(String email, String password) async {
    final bool demoLogin = isDemoLogin(email, password);
    await _run(() async {
      session = await _repository.login(email, password);
      filter = await _repository.loadFilter() ?? _defaultHistoryFilter();
      kwhPrice = await _repository.loadKwhPrice();
      currencyCode = await _repository.loadCurrencyCode() ?? 'EUR';
      historyColumns =
          await _repository.loadHistoryColumns() ?? HistoryColumn.values;
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      await _saveFilter();
      message = 'Logged in as ${session!.email}.';
      await refreshHistory();
      await _analytics?.logLoginSuccess(isDemo: demoLogin);
      if (demoLogin) {
        await _analytics?.logDemoLogin();
      }
    });
    if (error != null) {
      await _analytics?.logLoginFailed(isDemo: demoLogin);
    }
  }

  Future<void> logout() async {
    await _run(() async {
      await _repository.logout();
      session = null;
      kwhPrice = null;
      currencyCode = 'EUR';
      chargers = const <Charger>[];
      sessions = const <ChargeSession>[];
      totals = HistoryTotals.empty;
      historyPeriodOptions = _emptyHistoryPeriodOptions();
      message = 'Logged out.';
    });
  }

  Future<void> deleteStoredData() async {
    await _run(() async {
      await _repository.deleteStoredData();
      _clearSessionState();
      message = 'Stored data deleted.';
    });
  }

  Future<void> setKwhPrice(double? price) async {
    await _run(() async {
      kwhPrice = price;
      await _repository.saveKwhPrice(price);
      message = price == null
          ? 'kWh price cleared.'
          : 'kWh price saved as ${price.toStringAsFixed(4)}.';
      await refreshHistory();
    });
  }

  Future<void> setCostSettings({
    required double? kwhPrice,
    required String currencyCode,
  }) async {
    await _run(() async {
      this.kwhPrice = kwhPrice;
      this.currencyCode = _normalizeCurrencyCode(currencyCode);
      await _repository.saveKwhPrice(kwhPrice);
      await _repository.saveCurrencyCode(this.currencyCode);
      message = kwhPrice == null
          ? 'Cost settings saved.'
          : 'Cost settings saved as ${this.currencyCode} ${kwhPrice.toStringAsFixed(4)} per kWh.';
      await refreshHistory();
    });
  }

  Future<void> syncChargers() async {
    await _run(() async {
      chargers = await _repository.syncChargers();
      _ensureSelectedCharger();
      await refreshHistoryPeriodOptions();
      _ensureSelectedPeriodValue();
      await _saveFilter();
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
      await _saveFilter();
      message = '${chargers.length} chargers updated, $count sessions fetched.';
      await refreshHistory();
      await _analytics?.logSyncCompleted(
        chargerCount: chargers.length,
        sessionCount: count,
      );
    }, syncingHistory: true);
    if (error != null) {
      await _analytics?.logSyncFailed();
    }
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
      await _saveFilter();
      await refreshHistory();
      await _analytics?.logSyncCompleted(
        chargerCount: chargers.length,
        sessionCount: count,
      );
    }, syncingHistory: true);
    if (error != null) {
      await _analytics?.logSyncFailed();
    }
  }

  Future<void> setFilter(HistoryFilter value) async {
    filter = value;
    _ensureSelectedCharger();
    await refreshHistoryPeriodOptions();
    _ensureSelectedPeriodValue();
    await _saveFilter();
    notifyListeners();
    await refreshHistory();
    await _analytics?.logFilterChanged(filter);
  }

  Future<void> setHistoryColumns(List<HistoryColumn> columns) async {
    if (columns.isEmpty) {
      return;
    }
    historyColumns = List<HistoryColumn>.unmodifiable(columns);
    if (session != null) {
      await _repository.saveHistoryColumns(historyColumns);
    }
    notifyListeners();
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
    final List<ChargeSession> loadedSessions = _applyKwhPriceToSessions(
      await _repository.loadChargeHistory(activeFilter),
    );
    final HistoryTotals loadedTotals = _applyKwhPriceToTotals(
      await _repository.loadHistoryTotals(activeFilter),
    );
    if (refreshId != _historyRefreshId || filter != activeFilter) {
      return;
    }
    sessions = loadedSessions;
    totals = loadedTotals;
    notifyListeners();
  }

  Future<void> trackPdfExported() async {
    await _analytics?.logPdfExported(
      sessionCount: sessions.length,
      visibleColumnCount: historyColumns.length,
    );
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

  Future<void> _saveFilter() async {
    if (session != null) {
      await _repository.saveFilter(filter);
    }
  }

  List<ChargeSession> _applyKwhPriceToSessions(List<ChargeSession> sessions) {
    final double? price = kwhPrice;
    if (price == null) {
      return sessions;
    }
    return sessions
        .map(
          (ChargeSession session) => ChargeSession(
            id: session.id,
            chargerId: session.chargerId,
            chargerName: session.chargerName,
            userName: session.userName,
            startTime: session.startTime,
            endTime: session.endTime,
            energyKwh: session.energyKwh,
            durationSeconds: session.durationSeconds,
            cost: session.energyKwh == null ? null : session.energyKwh! * price,
          ),
        )
        .toList();
  }

  HistoryTotals _applyKwhPriceToTotals(HistoryTotals totals) {
    final double? price = kwhPrice;
    if (price == null) {
      return totals;
    }
    return HistoryTotals(
      sessions: totals.sessions,
      energyKwh: totals.energyKwh,
      durationSeconds: totals.durationSeconds,
      cost: totals.energyKwh == null ? null : totals.energyKwh! * price,
    );
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
    } on LoginRequiredException {
      try {
        await _repository.logout();
      } on Object {
        // The local UI state should still move back to logged out.
      }
      _clearSessionState();
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      isLoading = false;
      isBusy = false;
      isSyncingHistory = false;
      notifyListeners();
    }
  }

  void _clearSessionState() {
    session = null;
    kwhPrice = null;
    currencyCode = 'EUR';
    historyColumns = HistoryColumn.values;
    chargers = const <Charger>[];
    sessions = const <ChargeSession>[];
    totals = HistoryTotals.empty;
    historyPeriodOptions = _emptyHistoryPeriodOptions();
    filter = filter.copyWith(clearCharger: true);
    message = null;
    error = null;
  }
}

String _normalizeCurrencyCode(String value) {
  final String normalized = value.trim().toUpperCase();
  return normalized.isEmpty ? 'EUR' : normalized;
}

HistoryFilter _defaultHistoryFilter() {
  return HistoryFilter(periodValue: defaultPeriodValue(HistoryPeriod.all));
}

Map<HistoryPeriod, List<String>> _emptyHistoryPeriodOptions() {
  return <HistoryPeriod, List<String>>{
    HistoryPeriod.year: <String>[],
    HistoryPeriod.quarter: <String>[],
    HistoryPeriod.month: <String>[],
    HistoryPeriod.week: <String>[],
  };
}
