import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';

class AppAnalytics {
  AppAnalytics(this._analytics);

  final FirebaseAnalytics _analytics;

  Future<void> logLoginSuccess({required bool isDemo}) {
    return _logEvent(
      'login_success',
      parameters: <String, Object>{'login_type': isDemo ? 'demo' : 'zaptec'},
    );
  }

  Future<void> logLoginFailed({required bool isDemo}) {
    return _logEvent(
      'login_failed',
      parameters: <String, Object>{'login_type': isDemo ? 'demo' : 'zaptec'},
    );
  }

  Future<void> logDemoLogin() {
    return _logEvent('demo_login');
  }

  Future<void> logSyncCompleted({
    required int chargerCount,
    required int sessionCount,
  }) {
    return _logEvent(
      'sync_completed',
      parameters: <String, Object>{
        'charger_count': chargerCount,
        'session_count': sessionCount,
      },
    );
  }

  Future<void> logSyncFailed() {
    return _logEvent('sync_failed');
  }

  Future<void> logFilterChanged(HistoryFilter filter) {
    return _logEvent(
      'filter_changed',
      parameters: <String, Object>{
        'period': filter.period.name,
        'time_field': filter.timeField.name,
        'has_charger_filter': filter.chargerId == null ? 0 : 1,
        'has_custom_dates': filter.startDate != null || filter.endDate != null
            ? 1
            : 0,
      },
    );
  }

  Future<void> logPdfExported({
    required int sessionCount,
    required int visibleColumnCount,
  }) {
    return _logEvent(
      'pdf_exported',
      parameters: <String, Object>{
        'session_count': sessionCount,
        'visible_column_count': visibleColumnCount,
      },
    );
  }

  Future<void> _logEvent(String name, {Map<String, Object>? parameters}) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } on Object catch (error) {
      debugPrint('Firebase Analytics event skipped: $name: $error');
    }
  }
}
