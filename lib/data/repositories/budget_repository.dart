import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../models/budget.dart';

/// Handles CRUD for budgets via the REST API.
/// Endpoint: /budgets — docs/API_CONTRACT.md §Budgets.
///
/// Budgets are always attached to the active tracking period (the backend
/// resolves the period automatically). Online-only for v1 (same pattern as
/// categories and accounts).
class BudgetRepository {
  const BudgetRepository(this._dio);

  final Dio _dio;

  // -------------------------------------------------------------------------
  // List — GET /budgets?tracking_period_id= (default: active period)
  // -------------------------------------------------------------------------

  Future<List<Budget>> list({String? trackingPeriodId}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/budgets',
      queryParameters: trackingPeriodId != null
          ? {'tracking_period_id': trackingPeriodId}
          : null,
    );
    final items = resp.data!['budgets'] as List<dynamic>;
    return items.cast<Map<String, dynamic>>().map(Budget.fromJson).toList();
  }

  // -------------------------------------------------------------------------
  // Get — GET /budgets/:id
  // -------------------------------------------------------------------------

  Future<Budget> get(String id) async {
    final resp = await _dio.get<Map<String, dynamic>>('/budgets/$id');
    return Budget.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Create — POST /budgets → 201 / 409 (duplicate) / 422 (business rule)
  // -------------------------------------------------------------------------

  Future<Budget> create({
    required Decimal amount,
    String? categoryId,
    String? currency,
    Decimal? alertThresholdWarning,
    Decimal? alertThresholdCritical,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'amount': amount.toStringAsFixed(2),
      'category_id': categoryId,
      'currency': currency ?? 'COP',
      'alert_threshold_warning':
          alertThresholdWarning?.toStringAsFixed(2) ?? '80.00',
      'alert_threshold_critical':
          alertThresholdCritical?.toStringAsFixed(2) ?? '100.00',
      'notes': notes,
    };
    final resp = await _dio.post<Map<String, dynamic>>('/budgets', data: body);
    return Budget.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Update — PUT /budgets/:id → 200 / 409 / 422 (closed period)
  // -------------------------------------------------------------------------

  Future<Budget> update(
    String id, {
    required Decimal amount,
    String? categoryId,
    String? currency,
    Decimal? alertThresholdWarning,
    Decimal? alertThresholdCritical,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'amount': amount.toStringAsFixed(2),
      'category_id': categoryId,
      'currency': currency ?? 'COP',
      'alert_threshold_warning':
          alertThresholdWarning?.toStringAsFixed(2) ?? '80.00',
      'alert_threshold_critical':
          alertThresholdCritical?.toStringAsFixed(2) ?? '100.00',
      'notes': notes,
    };
    final resp = await _dio.put<Map<String, dynamic>>(
      '/budgets/$id',
      data: body,
    );
    return Budget.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Delete — DELETE /budgets/:id → 204 / 422 (closed period)
  // -------------------------------------------------------------------------

  Future<void> delete(String id) async {
    await _dio.delete<void>('/budgets/$id');
  }
}
