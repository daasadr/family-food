import 'package:intl/intl.dart';

/// Datum ve tvaru YYYY-MM-DD — formát, kterým se s API domlouváme.
String apiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

DateTime parseApiDate(String value) => DateFormat('yyyy-MM-dd').parseStrict(value);

DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Pondělí téhož týdne.
DateTime startOfWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day).subtract(
      Duration(days: date.weekday - DateTime.monday),
    );

const _weekdayNames = [
  'pondělí',
  'úterý',
  'středa',
  'čtvrtek',
  'pátek',
  'sobota',
  'neděle',
];

const _weekdayShort = ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'];

const _monthNames = [
  'ledna',
  'února',
  'března',
  'dubna',
  'května',
  'června',
  'července',
  'srpna',
  'září',
  'října',
  'listopadu',
  'prosince',
];

String weekdayName(DateTime date) => _weekdayNames[date.weekday - 1];

String weekdayShort(DateTime date) => _weekdayShort[date.weekday - 1];

/// „úterý 4. srpna“
String longDate(DateTime date) =>
    '${weekdayName(date)} ${date.day}. ${_monthNames[date.month - 1]}';

/// „4. 8.“
String shortDate(DateTime date) => '${date.day}. ${date.month}.';

/// „4.–10. srpna“ pro hlavičku týdne.
String weekRangeLabel(DateTime start) {
  final end = start.add(const Duration(days: 6));
  if (start.month == end.month) {
    return '${start.day}.–${end.day}. ${_monthNames[start.month - 1]}';
  }
  return '${start.day}. ${_monthNames[start.month - 1]} – '
      '${end.day}. ${_monthNames[end.month - 1]}';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// „dnes 14:30“ / „4. 8. 14:30“ pro komentáře.
String commentTimestamp(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final clock = DateFormat('H:mm').format(local);
  if (isSameDay(local, now)) return 'dnes $clock';
  if (isSameDay(local, now.subtract(const Duration(days: 1)))) {
    return 'včera $clock';
  }
  return '${shortDate(local)} $clock';
}
