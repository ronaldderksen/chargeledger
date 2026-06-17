enum HistoryPeriod { all, year, quarter, month, week, custom }

enum HistoryTimeField { startTime, endTime }

class ZaptecSession {
  const ZaptecSession({
    required this.customerId,
    required this.email,
    required this.accessToken,
    required this.expiresAt,
  });

  final String customerId;
  final String email;
  final String accessToken;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().toUtc().isBefore(expiresAt.toUtc());
}

class Charger {
  const Charger({
    required this.id,
    required this.name,
    this.serialNumber,
    this.installationId,
  });

  final String id;
  final String name;
  final String? serialNumber;
  final String? installationId;
}

class ChargeSession {
  const ChargeSession({
    required this.id,
    this.chargerId,
    this.chargerName,
    this.userName,
    this.startTime,
    this.endTime,
    this.energyKwh,
    this.durationSeconds,
    this.cost,
  });

  final String id;
  final String? chargerId;
  final String? chargerName;
  final String? userName;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? energyKwh;
  final int? durationSeconds;
  final double? cost;
}

class HistoryFilter {
  const HistoryFilter({
    this.period = HistoryPeriod.all,
    this.timeField = HistoryTimeField.startTime,
    this.periodValue,
    this.startDate,
    this.endDate,
    this.chargerId,
  });

  final HistoryPeriod period;
  final HistoryTimeField timeField;
  final String? periodValue;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? chargerId;

  HistoryFilter copyWith({
    HistoryPeriod? period,
    HistoryTimeField? timeField,
    String? periodValue,
    DateTime? startDate,
    DateTime? endDate,
    String? chargerId,
    bool clearPeriodValue = false,
    bool clearDates = false,
    bool clearCharger = false,
  }) {
    return HistoryFilter(
      period: period ?? this.period,
      timeField: timeField ?? this.timeField,
      periodValue: clearPeriodValue ? null : periodValue ?? this.periodValue,
      startDate: clearDates ? null : startDate ?? this.startDate,
      endDate: clearDates ? null : endDate ?? this.endDate,
      chargerId: clearCharger ? null : chargerId ?? this.chargerId,
    );
  }
}

class HistoryTotals {
  const HistoryTotals({
    required this.sessions,
    this.energyKwh,
    this.durationSeconds,
    this.cost,
  });

  final int sessions;
  final double? energyKwh;
  final int? durationSeconds;
  final double? cost;

  static const empty = HistoryTotals(sessions: 0);
}
