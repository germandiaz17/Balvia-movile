import 'package:dio/dio.dart';

import '../models/insight.dart';
import '../models/period_summary.dart';
import '../models/tracking_period.dart';

/// Handles read-only access to tracking periods.
/// The backend manages lifecycle automatically (lazy-close, auto-open).
/// Mirrors docs/API_CONTRACT.md §Tracking periods.
class TrackingPeriodRepository {
  TrackingPeriodRepository(this._dio);

  final Dio _dio;

  /// Returns the currently active tracking period.
  /// The backend applies lazy-close: if the period already expired it closes it
  /// and returns the next one.
  /// Throws a DioException (422) if there is no active period.
  Future<TrackingPeriod> getActive() async {
    final res = await _dio.get('/tracking-periods/active');
    return TrackingPeriod.fromJson(res.data as Map<String, dynamic>);
  }

  /// Returns a summary for [periodId] with the given [view].
  /// [view] must be "full" | "biweekly" | "weekly" (defaults to "full").
  Future<PeriodSummary> getSummary(
    String periodId, {
    String view = 'full',
  }) async {
    final res = await _dio.get(
      '/tracking-periods/$periodId/summary',
      queryParameters: {'view': view},
    );
    return PeriodSummary.fromJson(res.data as Map<String, dynamic>);
  }

  /// Returns the insights for [periodId]. For the active period the backend
  /// lazily computes the "during" insights. Insights are non-critical and
  /// online-only. Returns [] when the payload is missing.
  Future<List<Insight>> getInsights(String periodId) async {
    final res = await _dio.get('/tracking-periods/$periodId/insights');
    final items = (res.data as Map<String, dynamic>)['insights'] as List?;
    if (items == null) return [];
    return items
        .map((e) => Insight.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns all tracking periods for the authenticated user.
  Future<List<TrackingPeriod>> list() async {
    final res = await _dio.get('/tracking-periods');
    final items =
        (res.data as Map<String, dynamic>)['tracking_periods'] as List;
    return items
        .map((e) => TrackingPeriod.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
