import 'models.dart';

String defaultPeriodValue(HistoryPeriod period, [DateTime? now]) {
  final DateTime today = now ?? DateTime.now();
  return switch (period) {
    HistoryPeriod.year => today.year.toString(),
    HistoryPeriod.quarter => '${today.year}-Q${((today.month - 1) ~/ 3) + 1}',
    HistoryPeriod.month =>
      '${today.year}-${today.month.toString().padLeft(2, '0')}',
    HistoryPeriod.week => _isoWeekValue(today),
    HistoryPeriod.all || HistoryPeriod.custom => '',
  };
}

({DateTime? start, DateTime? end}) periodBounds(HistoryFilter filter) {
  final String value = filter.periodValue?.trim().isNotEmpty == true
      ? filter.periodValue!.trim()
      : defaultPeriodValue(filter.period);
  try {
    switch (filter.period) {
      case HistoryPeriod.year:
        final int year = int.parse(value);
        return (start: DateTime(year), end: DateTime(year + 1));
      case HistoryPeriod.quarter:
        final List<String> parts = value.split('-Q');
        final int year = int.parse(parts[0]);
        final int quarter = int.parse(parts[1]);
        if (quarter < 1 || quarter > 4) {
          return (start: null, end: null);
        }
        final int month = ((quarter - 1) * 3) + 1;
        final int endMonth = month + 3;
        return (
          start: DateTime(year, month),
          end: endMonth > 12 ? DateTime(year + 1) : DateTime(year, endMonth),
        );
      case HistoryPeriod.month:
        final List<String> parts = value.split('-');
        final int year = int.parse(parts[0]);
        final int month = int.parse(parts[1]);
        return (
          start: DateTime(year, month),
          end: month == 12 ? DateTime(year + 1) : DateTime(year, month + 1),
        );
      case HistoryPeriod.week:
        final List<String> parts = value.split('-W');
        final DateTime start = _dateFromIsoWeek(
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        return (start: start, end: start.add(const Duration(days: 7)));
      case HistoryPeriod.custom:
        return (
          start: filter.startDate == null
              ? null
              : DateTime(
                  filter.startDate!.year,
                  filter.startDate!.month,
                  filter.startDate!.day,
                ),
          end: filter.endDate == null
              ? null
              : DateTime(
                  filter.endDate!.year,
                  filter.endDate!.month,
                  filter.endDate!.day,
                ).add(const Duration(days: 1)),
        );
      case HistoryPeriod.all:
        return (start: null, end: null);
    }
  } on Object {
    return (start: null, end: null);
  }
}

String shiftPeriodValue(HistoryPeriod period, String value, int step) {
  try {
    switch (period) {
      case HistoryPeriod.year:
        return (int.parse(value) + step).toString();
      case HistoryPeriod.quarter:
        final List<String> parts = value.split('-Q');
        int year = int.parse(parts[0]);
        int quarter = int.parse(parts[1]) + step;
        while (quarter < 1) {
          quarter += 4;
          year -= 1;
        }
        while (quarter > 4) {
          quarter -= 4;
          year += 1;
        }
        return '$year-Q$quarter';
      case HistoryPeriod.month:
        final List<String> parts = value.split('-');
        int year = int.parse(parts[0]);
        int month = int.parse(parts[1]) + step;
        while (month < 1) {
          month += 12;
          year -= 1;
        }
        while (month > 12) {
          month -= 12;
          year += 1;
        }
        return '$year-${month.toString().padLeft(2, '0')}';
      case HistoryPeriod.week:
        final List<String> parts = value.split('-W');
        final DateTime start = _dateFromIsoWeek(
          int.parse(parts[0]),
          int.parse(parts[1]),
        ).add(Duration(days: 7 * step));
        return _isoWeekValue(start);
      case HistoryPeriod.all:
      case HistoryPeriod.custom:
        return value;
    }
  } on Object {
    return defaultPeriodValue(period);
  }
}

List<String> periodOptions(HistoryPeriod period) {
  final DateTime today = DateTime.now();
  final List<String> options = <String>[];
  switch (period) {
    case HistoryPeriod.year:
      for (int year = today.year + 1; year > today.year - 10; year--) {
        options.add(year.toString());
      }
    case HistoryPeriod.quarter:
      int year = today.year;
      int quarter = ((today.month - 1) ~/ 3) + 1;
      for (int i = 0; i < 24; i++) {
        options.add('$year-Q$quarter');
        quarter--;
        if (quarter == 0) {
          quarter = 4;
          year--;
        }
      }
    case HistoryPeriod.month:
      int year = today.year;
      int month = today.month;
      for (int i = 0; i < 36; i++) {
        options.add('$year-${month.toString().padLeft(2, '0')}');
        month--;
        if (month == 0) {
          month = 12;
          year--;
        }
      }
    case HistoryPeriod.week:
      DateTime monday = today.subtract(Duration(days: today.weekday - 1));
      for (int i = 0; i < 52; i++) {
        options.add(_isoWeekValue(monday));
        monday = monday.subtract(const Duration(days: 7));
      }
    case HistoryPeriod.all:
    case HistoryPeriod.custom:
      break;
  }
  return options;
}

String _isoWeekValue(DateTime date) {
  final int week = _isoWeekNumber(date);
  final int year = _isoWeekYear(date);
  return '$year-W${week.toString().padLeft(2, '0')}';
}

int _isoWeekYear(DateTime date) {
  final DateTime thursday = date.add(Duration(days: 4 - date.weekday));
  return thursday.year;
}

int _isoWeekNumber(DateTime date) {
  final DateTime thursday = date.add(Duration(days: 4 - date.weekday));
  final DateTime firstThursday = DateTime(thursday.year, 1, 4);
  final DateTime firstWeekStart = firstThursday.subtract(
    Duration(days: firstThursday.weekday - 1),
  );
  return (thursday.difference(firstWeekStart).inDays ~/ 7) + 1;
}

DateTime _dateFromIsoWeek(int year, int week) {
  final DateTime fourthJanuary = DateTime(year, 1, 4);
  final DateTime firstMonday = fourthJanuary.subtract(
    Duration(days: fourthJanuary.weekday - 1),
  );
  return firstMonday.add(Duration(days: (week - 1) * 7));
}
