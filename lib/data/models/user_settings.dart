/// The authenticated user's preferences. Mirrors `settingsResponse` in
/// internal/handlers/user_settings.go.
///
/// Domain rule 8: changing the tracking configuration never reshapes the period
/// that is currently running — it applies to the next one. The backend states
/// that explicitly via [appliesToNextPeriod] and [activePeriodEndDate] so the UI
/// can name the exact cut-off date instead of a vague "applies later".
class UserSettings {
  const UserSettings({
    required this.trackingStartDay,
    required this.trackingDurationDays,
    required this.defaultCurrency,
    required this.countryCode,
    required this.locale,
    required this.theme,
    required this.defaultPeriodView,
    required this.subscriptionTier,
    required this.appliesToNextPeriod,
    this.updatedAt,
    this.activePeriodEndDate,
  });

  /// Day-of-month anchor. Currently informational: ClosePeriodTx always starts
  /// the next period the day after the previous one ends, so this value is
  /// recorded but does not drive the rollover.
  final int trackingStartDay;

  /// 28–31, enforced by chk_tracking_duration.
  final int trackingDurationDays;

  final String defaultCurrency;
  final String countryCode;
  final String locale;
  final String theme;
  final String defaultPeriodView;

  /// Server-controlled; not editable from the app.
  final String subscriptionTier;

  final DateTime? updatedAt;

  /// Always true — kept on the wire so the client does not hardcode rule 8.
  final bool appliesToNextPeriod;

  /// Last day of the period currently running. Null when there is none.
  final DateTime? activePeriodEndDate;

  /// The day the next period begins, i.e. when a change takes effect.
  DateTime? get nextPeriodStartDate =>
      activePeriodEndDate?.add(const Duration(days: 1));

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    trackingStartDay: json['tracking_start_day'] as int,
    trackingDurationDays: json['tracking_duration_days'] as int,
    defaultCurrency: json['default_currency'] as String? ?? 'COP',
    countryCode: json['country_code'] as String? ?? 'CO',
    locale: json['locale'] as String? ?? 'es-CO',
    theme: json['theme'] as String? ?? 'system',
    defaultPeriodView: json['default_period_view'] as String? ?? 'full',
    subscriptionTier: json['subscription_tier'] as String? ?? 'free',
    appliesToNextPeriod: json['applies_to_next_period'] as bool? ?? true,
    updatedAt: (json['updated_at'] as String?)?.isNotEmpty ?? false
        ? DateTime.parse(json['updated_at'] as String)
        : null,
    activePeriodEndDate: json['active_period_end_date'] == null
        ? null
        : DateTime.parse(json['active_period_end_date'] as String),
  );
}

/// Durations the schema accepts (chk_tracking_duration BETWEEN 28 AND 31).
const kTrackingDurations = <int>[28, 29, 30, 31];

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "13 de agosto" — used in the copy that tells the user when a change lands.
String longDate(DateTime d) => '${d.day} de ${_monthNames[d.month - 1]}';
