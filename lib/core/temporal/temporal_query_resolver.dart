/// Represents a resolved timestamp range for temporal memory queries.
class TimeRange {
  final int startTime; // epoch milliseconds
  final int endTime; // epoch milliseconds
  final String label;

  TimeRange({
    required this.startTime,
    required this.endTime,
    required this.label,
  });
}

/// Resolves natural language time expressions into concrete SQLite query timestamp ranges.
class TemporalQueryResolver {
  /// Analyzes query text and extracts time constraints.
  static TimeRange? resolveTimeConstraint(String query, {DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    final text = query.toLowerCase();

    // 1. All-time / Historical expressions
    if (text.contains('all time') ||
        text.contains('historical') ||
        text.contains('all data') ||
        text.contains('all memories') ||
        text.contains('entire history') ||
        text.contains('oldest') ||
        text.contains('lifetime') ||
        text.contains('long ago') ||
        text.contains('long back')) {
      return TimeRange(startTime: 0, endTime: now.millisecondsSinceEpoch, label: 'all time');
    }

    // 2. Year ago / years before: "1yr before", "1 year ago", "10yr before", "10 years ago", "5 yrs ago"
    final yearRegex = RegExp(r'(\d+|one|two|three|four|five|ten)\s*(?:years?|yrs?)\s*(?:ago|before)');
    final yearMatch = yearRegex.firstMatch(text);
    if (yearMatch != null) {
      final word = yearMatch.group(1)!;
      int years = 1;
      if (int.tryParse(word) != null) {
        years = int.parse(word);
      } else {
        switch (word) {
          case 'one': years = 1; break;
          case 'two': years = 2; break;
          case 'three': years = 3; break;
          case 'four': years = 4; break;
          case 'five': years = 5; break;
          case 'ten': years = 10; break;
        }
      }
      final targetYear = now.year - years;
      final start = DateTime(targetYear, 1, 1).millisecondsSinceEpoch;
      final end = DateTime(targetYear, 12, 31, 23, 59, 59).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: '$years ${years == 1 ? "year" : "years"} ago');
    }

    // 3. Last year
    if (text.contains('last year') || text.contains('previous year')) {
      final targetYear = now.year - 1;
      final start = DateTime(targetYear, 1, 1).millisecondsSinceEpoch;
      final end = DateTime(targetYear, 12, 31, 23, 59, 59).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: 'last year');
    }

    // 4. Explicit 4-digit year (e.g. "in 2024", "2023", "2018", "2015")
    final explicitYearRegex = RegExp(r'\b(19\d\d|20\d\d)\b');
    final explicitYearMatch = explicitYearRegex.firstMatch(text);
    if (explicitYearMatch != null) {
      final y = int.parse(explicitYearMatch.group(1)!);
      final start = DateTime(y, 1, 1).millisecondsSinceEpoch;
      final end = DateTime(y, 12, 31, 23, 59, 59).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: '$y');
    }

    // 5. Month ago / months before: "1 month ago", "6 months ago", "2mos before"
    final monthRegex = RegExp(r'(\d+|one|two|three|six)\s*(?:months?|mos?)\s*(?:ago|before)');
    final monthMatch = monthRegex.firstMatch(text);
    if (monthMatch != null) {
      final word = monthMatch.group(1)!;
      int months = 1;
      if (int.tryParse(word) != null) {
        months = int.parse(word);
      } else {
        switch (word) {
          case 'one': months = 1; break;
          case 'two': months = 2; break;
          case 'three': months = 3; break;
          case 'six': months = 6; break;
        }
      }
      final target = DateTime(now.year, now.month - months, 1);
      final nextMonth = DateTime(target.year, target.month + 1, 1);
      final start = target.millisecondsSinceEpoch;
      final end = nextMonth.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: '$months months ago');
    }

    if (text.contains('today')) {
      final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final end = now.millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: 'today');
    }

    if (text.contains('yesterday')) {
      final yesterday = now.subtract(const Duration(days: 1));
      final start = DateTime(yesterday.year, yesterday.month, yesterday.day).millisecondsSinceEpoch;
      final end = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: 'yesterday');
    }

    if (text.contains('last week')) {
      final start = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final end = now.millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: 'last week');
    }

    if (text.contains('this month')) {
      final start = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      final end = now.millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: 'this month');
    }

    // "3 days ago", "three days ago"
    final daysAgoRegex = RegExp(r'(\d+|three|two|four|five)\s+days?\s+ago');
    final match = daysAgoRegex.firstMatch(text);
    if (match != null) {
      int days = 3;
      final word = match.group(1)!;
      if (int.tryParse(word) != null) {
        days = int.parse(word);
      } else if (word == 'two') {
        days = 2;
      } else if (word == 'three') {
        days = 3;
      } else if (word == 'four') {
        days = 4;
      } else if (word == 'five') {
        days = 5;
      }

      final target = now.subtract(Duration(days: days));
      final start = DateTime(target.year, target.month, target.day).millisecondsSinceEpoch;
      final end = DateTime(target.year, target.month, target.day, 23, 59, 59).millisecondsSinceEpoch;
      return TimeRange(startTime: start, endTime: end, label: '$days days ago');
    }

    // "last Tuesday", "last Monday", etc.
    final weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    for (int i = 0; i < weekdays.length; i++) {
      if (text.contains('last ${weekdays[i]}')) {
        int targetWeekday = i + 1;
        int daysBack = (now.weekday - targetWeekday) % 7;
        if (daysBack <= 0) daysBack += 7;
        final target = now.subtract(Duration(days: daysBack));
        final start = DateTime(target.year, target.month, target.day).millisecondsSinceEpoch;
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59).millisecondsSinceEpoch;
        return TimeRange(startTime: start, endTime: end, label: 'last ${weekdays[i]}');
      }
    }

    return null;
  }
}
