import 'package:dio/dio.dart';

import '../models/user_settings.dart';

/// Reads and updates the authenticated user's preferences.
/// Endpoint: /settings (a singleton resource — no id in the path).
class UserSettingsRepository {
  const UserSettingsRepository(this._dio);

  final Dio _dio;

  Future<UserSettings> get() async {
    final resp = await _dio.get<Map<String, dynamic>>('/settings');
    return UserSettings.fromJson(resp.data!);
  }

  /// Partial update: only the fields you pass travel, because the SQL side uses
  /// COALESCE(narg, column) — a key that is absent leaves the column alone,
  /// while sending it as null would too, but sending everything would force the
  /// caller to know every current value. Keep it sparse.
  ///
  /// Changing [trackingDurationDays] or [trackingPeriodMode] does not touch the
  /// running period; it applies to the next one (domain rule 8). The one
  /// exception is a first period with no transactions, which the backend
  /// reshapes on the spot and reports back as `appliesToNextPeriod == false`.
  Future<UserSettings> update({
    int? trackingStartDay,
    int? trackingDurationDays,
    String? trackingPeriodMode,
    String? defaultCurrency,
    String? locale,
    String? theme,
    String? defaultPeriodView,
  }) async {
    final body = <String, dynamic>{};
    if (trackingStartDay != null) body['tracking_start_day'] = trackingStartDay;
    if (trackingDurationDays != null) {
      body['tracking_duration_days'] = trackingDurationDays;
    }
    if (trackingPeriodMode != null) {
      body['tracking_period_mode'] = trackingPeriodMode;
    }
    if (defaultCurrency != null) body['default_currency'] = defaultCurrency;
    if (locale != null) body['locale'] = locale;
    if (theme != null) body['theme'] = theme;
    if (defaultPeriodView != null) {
      body['default_period_view'] = defaultPeriodView;
    }

    final resp = await _dio.put<Map<String, dynamic>>('/settings', data: body);
    return UserSettings.fromJson(resp.data!);
  }
}
