import 'user_settings.dart' show kPeriodModeCalendar, kPeriodModeRolling;

/// A tracking period (seguimiento). The backend manages its lifecycle;
/// clients are read-only. Mirrors the contract object in
/// docs/API_CONTRACT.md §Tracking periods.
class TrackingPeriod {
  const TrackingPeriod({
    required this.id,
    required this.sequenceNumber,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.configStartDay,
    required this.configDurationDays,
    required this.configPeriodMode,
    required this.isTransition,
    this.closedAt,
  });

  final String id;
  final int sequenceNumber;

  /// YYYY-MM-DD
  final String startDate;

  /// YYYY-MM-DD
  final String endDate;

  /// active | closed
  final String status;

  final int configStartDay;
  final int configDurationDays;

  /// The mode this period was generated under: [kPeriodModeRolling] or
  /// [kPeriodModeCalendar]. Decides whether the UI titles it with a month name
  /// or a date range.
  final String configPeriodMode;

  /// A one-off bridge created when the user switched period mode. Its length is
  /// deliberately outside the usual 28–31 days, so it must be presented as a
  /// transition rather than a normal period.
  final bool isTransition;

  /// RFC3339 when closed; null when active.
  final DateTime? closedAt;

  bool get isActive => status == 'active';

  /// True when this period is a whole calendar month, i.e. it can be named
  /// "agosto" instead of shown as a range. A bridge never qualifies.
  bool get isWholeCalendarMonth =>
      configPeriodMode == kPeriodModeCalendar && !isTransition;

  /// Total duration in days (inclusive of both endpoints).
  int get durationDays {
    final start = DateTime.parse(startDate);
    final end = DateTime.parse(endDate);
    return end.difference(start).inDays + 1;
  }

  /// Days elapsed since [startDate] (today – startDate, clamped to duration).
  int get daysElapsed {
    final start = DateTime.parse(startDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final elapsed = today.difference(start).inDays;
    return elapsed.clamp(0, durationDays);
  }

  /// Days remaining (0 when period has ended).
  int get daysRemaining => (durationDays - daysElapsed).clamp(0, durationDays);

  /// Progress through the period as a fraction [0, 1].
  double get progressFraction =>
      durationDays > 0 ? daysElapsed / durationDays : 0.0;

  factory TrackingPeriod.fromJson(Map<String, dynamic> json) => TrackingPeriod(
    id: json['id'] as String,
    sequenceNumber: json['sequence_number'] as int,
    startDate: json['start_date'] as String,
    endDate: json['end_date'] as String,
    status: json['status'] as String,
    configStartDay: json['config_start_day'] as int,
    configDurationDays: json['config_duration_days'] as int,
    configPeriodMode:
        json['config_period_mode'] as String? ?? kPeriodModeRolling,
    isTransition: json['is_transition'] as bool? ?? false,
    closedAt: json['closed_at'] != null
        ? DateTime.parse(json['closed_at'] as String)
        : null,
  );
}
