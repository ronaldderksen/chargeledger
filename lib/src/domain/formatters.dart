import 'package:intl/intl.dart';

final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

String displayText(Object? value) {
  if (value == null || value == '') {
    return '-';
  }
  return value.toString();
}

String displayDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return _dateTimeFormat.format(value.toLocal());
}

String displayDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return _dateFormat.format(value);
}

String displayNumber(num? value) {
  if (value == null) {
    return '-';
  }
  return value.toStringAsFixed(2);
}

String displayDuration(int? seconds) {
  if (seconds == null) {
    return '-';
  }
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}
