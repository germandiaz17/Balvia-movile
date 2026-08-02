import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../models/recurring_transaction.dart';
import '../models/savings_goal.dart' show formatDateOnly;

/// CRUD for recurring transaction templates. Endpoint: /recurring-transactions.
///
/// Online-only, like savings goals: /sync/push does not accept this entity.
///
/// ⚠️ [list] and [get] HAVE A SIDE EFFECT. Both handlers call
/// `engine.ProcessUserRecurring` before responding, which materialises every
/// overdue template into REAL transactions and advances next_due_date. Callers
/// should trigger a sync afterwards so those new transactions reach Drift and
/// show up in Movimientos and Inicio.
///
/// The client never computes next_due_date or creates occurrences — the engine
/// owns both.
class RecurringTransactionRepository {
  const RecurringTransactionRepository(this._dio);

  final Dio _dio;

  // -------------------------------------------------------------------------
  // List — GET /recurring-transactions (materialises overdue templates!)
  // -------------------------------------------------------------------------

  Future<List<RecurringTransaction>> list() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/recurring-transactions',
    );
    final items = resp.data!['recurring_transactions'] as List<dynamic>;
    return items
        .cast<Map<String, dynamic>>()
        .map(RecurringTransaction.fromJson)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Get — GET /recurring-transactions/:id (same side effect as list)
  // -------------------------------------------------------------------------

  Future<RecurringTransaction> get(String id) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/recurring-transactions/$id',
    );
    return RecurringTransaction.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Create — POST /recurring-transactions → 201 / 422
  // -------------------------------------------------------------------------

  Future<RecurringTransaction> create({
    required String accountId,
    required String name,
    required String transactionType,
    required Decimal amount,
    required String frequency,
    required DateTime startDate,
    String? categoryId,
    String? description,
    String? currency,
    int? customIntervalDays,
    int? dayOfMonth,
    int? dayOfWeek,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/recurring-transactions',
      data: _body(
        accountId: accountId,
        name: name,
        transactionType: transactionType,
        amount: amount,
        frequency: frequency,
        startDate: startDate,
        categoryId: categoryId,
        description: description,
        currency: currency,
        customIntervalDays: customIntervalDays,
        dayOfMonth: dayOfMonth,
        dayOfWeek: dayOfWeek,
        endDate: endDate,
        isActive: isActive,
      ),
    );
    return RecurringTransaction.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Update — PUT /recurring-transactions/:id → 200 / 422
  //
  // Full replace (recurringRequest requires account_id, name,
  // transaction_type, amount, frequency and start_date), and the service
  // recomputes next_due_date from start_date on every update — an edit can move
  // the next occurrence.
  // -------------------------------------------------------------------------

  Future<RecurringTransaction> update(
    String id, {
    required String accountId,
    required String name,
    required String transactionType,
    required Decimal amount,
    required String frequency,
    required DateTime startDate,
    String? categoryId,
    String? description,
    String? currency,
    int? customIntervalDays,
    int? dayOfMonth,
    int? dayOfWeek,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '/recurring-transactions/$id',
      data: _body(
        accountId: accountId,
        name: name,
        transactionType: transactionType,
        amount: amount,
        frequency: frequency,
        startDate: startDate,
        categoryId: categoryId,
        description: description,
        currency: currency,
        customIntervalDays: customIntervalDays,
        dayOfMonth: dayOfMonth,
        dayOfWeek: dayOfWeek,
        endDate: endDate,
        isActive: isActive,
      ),
    );
    return RecurringTransaction.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Delete — DELETE /recurring-transactions/:id → 204
  // -------------------------------------------------------------------------

  Future<void> delete(String id) async {
    await _dio.delete<void>('/recurring-transactions/$id');
  }

  /// Builds the shared create/update body. Frequency-specific hints only travel
  /// when the frequency actually uses them, so switching (say) monthly → weekly
  /// does not leave a stale day_of_month behind.
  Map<String, dynamic> _body({
    required String accountId,
    required String name,
    required String transactionType,
    required Decimal amount,
    required String frequency,
    required DateTime startDate,
    String? categoryId,
    String? description,
    String? currency,
    int? customIntervalDays,
    int? dayOfMonth,
    int? dayOfWeek,
    DateTime? endDate,
    required bool isActive,
  }) {
    return <String, dynamic>{
      'account_id': accountId,
      'category_id': categoryId,
      'name': name,
      'transaction_type': transactionType,
      'amount': amount.toStringAsFixed(2),
      'currency': currency ?? AppConfig.defaultCurrency,
      'description': description,
      'frequency': frequency,
      'custom_interval_days': frequency == 'custom' ? customIntervalDays : null,
      'day_of_month': frequency == 'monthly' ? dayOfMonth : null,
      'day_of_week': (frequency == 'weekly' || frequency == 'biweekly')
          ? dayOfWeek
          : null,
      'start_date': formatDateOnly(startDate),
      'end_date': endDate == null ? null : formatDateOnly(endDate),
      'is_active': isActive,
    };
  }
}
