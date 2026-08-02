import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../models/savings_goal.dart';

/// Result of adding a contribution: the backend returns the refreshed goal
/// alongside the new contribution, so the UI can update without a refetch.
typedef ContributionResult = ({
  SavingsGoal goal,
  GoalContribution contribution,
});

/// CRUD for savings goals via the REST API. Endpoint: /savings-goals.
///
/// Online-only, like budgets, accounts and categories: `/sync/push` only accepts
/// `entity_type: "transaction"`, so there is no offline write path for goals.
/// More importantly, `CreateContributionTx` updates current_amount and flips the
/// status to `achieved` atomically on the server — duplicating that client-side
/// would fork business logic.
///
/// Errors are not caught here; the UI turns them into messages with
/// `apiErrorMessage()`.
class SavingsGoalRepository {
  const SavingsGoalRepository(this._dio);

  final Dio _dio;

  // -------------------------------------------------------------------------
  // List — GET /savings-goals
  // -------------------------------------------------------------------------

  Future<List<SavingsGoal>> list() async {
    final resp = await _dio.get<Map<String, dynamic>>('/savings-goals');
    final items = resp.data!['savings_goals'] as List<dynamic>;
    return items
        .cast<Map<String, dynamic>>()
        .map(SavingsGoal.fromJson)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Get — GET /savings-goals/:id
  // -------------------------------------------------------------------------

  Future<SavingsGoal> get(String id) async {
    final resp = await _dio.get<Map<String, dynamic>>('/savings-goals/$id');
    return SavingsGoal.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Create — POST /savings-goals → 201 / 422 (target_date must beat start_date)
  // -------------------------------------------------------------------------

  Future<SavingsGoal> create({
    required String name,
    required Decimal targetAmount,
    required DateTime startDate,
    required DateTime targetDate,
    String? description,
    String? icon,
    String? color,
    String? currency,
    String? linkedAccountId,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'target_amount': targetAmount.toStringAsFixed(2),
      'start_date': formatDateOnly(startDate),
      'target_date': formatDateOnly(targetDate),
      'currency': currency ?? AppConfig.defaultCurrency,
      'description': description,
      'icon': icon,
      'color': color,
      'linked_account_id': linkedAccountId,
    };
    final resp = await _dio.post<Map<String, dynamic>>(
      '/savings-goals',
      data: body,
    );
    return SavingsGoal.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Update — PUT /savings-goals/:id → 200 / 422
  //
  // NOTE: this is a FULL REPLACE, not a patch. `goalUpdateRequest` requires
  // name, target_amount, target_date and status, and does NOT accept
  // start_date. Always preload the whole goal into the form before editing, or
  // fields the user did not touch will be overwritten.
  // -------------------------------------------------------------------------

  Future<SavingsGoal> update(
    String id, {
    required String name,
    required Decimal targetAmount,
    required DateTime targetDate,
    required String status,
    String? description,
    String? icon,
    String? color,
    String? linkedAccountId,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'target_amount': targetAmount.toStringAsFixed(2),
      'target_date': formatDateOnly(targetDate),
      'status': status,
      'description': description,
      'icon': icon,
      'color': color,
      'linked_account_id': linkedAccountId,
    };
    final resp = await _dio.put<Map<String, dynamic>>(
      '/savings-goals/$id',
      data: body,
    );
    return SavingsGoal.fromJson(resp.data!);
  }

  // -------------------------------------------------------------------------
  // Delete — DELETE /savings-goals/:id → 204
  // -------------------------------------------------------------------------

  Future<void> delete(String id) async {
    await _dio.delete<void>('/savings-goals/$id');
  }

  // -------------------------------------------------------------------------
  // Add contribution — POST /savings-goals/:id/contributions → 201
  //
  // Requires an active tracking period; without one the backend answers 422
  // ("no active tracking period"), which apiErrorMessage() surfaces verbatim.
  // Omitting the date lets the server default it to today.
  // -------------------------------------------------------------------------

  Future<ContributionResult> addContribution(
    String goalId, {
    required Decimal amount,
    DateTime? contributionDate,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'amount': amount.toStringAsFixed(2),
      if (contributionDate != null)
        'contribution_date': formatDateOnly(contributionDate),
      'notes': notes,
    };
    final resp = await _dio.post<Map<String, dynamic>>(
      '/savings-goals/$goalId/contributions',
      data: body,
    );
    final data = resp.data!;
    return (
      goal: SavingsGoal.fromJson(data['goal'] as Map<String, dynamic>),
      contribution: GoalContribution.fromJson(
        data['contribution'] as Map<String, dynamic>,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // List contributions — GET /savings-goals/:id/contributions
  // -------------------------------------------------------------------------

  Future<List<GoalContribution>> listContributions(String goalId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/savings-goals/$goalId/contributions',
    );
    final items = resp.data!['contributions'] as List<dynamic>;
    return items
        .cast<Map<String, dynamic>>()
        .map(GoalContribution.fromJson)
        .toList();
  }
}
