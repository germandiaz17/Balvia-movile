import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../models/transaction.dart';

/// Handles transaction API calls. Amount is Decimal on the client; it is
/// serialised as a string ("12000.00") for the backend — never a double.
class TransactionRepository {
  TransactionRepository(this._dio);

  final Dio _dio;

  /// Builds the request body shared by create and update.
  Map<String, dynamic> _buildBody({
    required String accountId,
    required String transactionType,
    required Decimal amount,
    String currency = 'COP',
    String? categoryId,
    String? description,
    String? notes,
    String? transactionDate,
    String? transferAccountId,
    String? clientId,
  }) {
    final body = <String, dynamic>{
      'account_id': accountId,
      'transaction_type': transactionType,
      'amount': amount.toStringAsFixed(2),
      'currency': currency,
    };
    if (categoryId != null && categoryId.isNotEmpty) {
      body['category_id'] = categoryId;
    }
    if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    if (notes != null && notes.isNotEmpty) body['notes'] = notes;
    if (transactionDate != null) body['transaction_date'] = transactionDate;
    if (transferAccountId != null) {
      body['transfer_account_id'] = transferAccountId;
    }
    if (clientId != null) body['client_id'] = clientId;
    return body;
  }

  /// Creates a new transaction and returns the created object.
  /// [amount] must be positive; the sign/direction is conveyed by
  /// [transactionType] ("income" | "expense" | "transfer").
  Future<Transaction> create({
    required String accountId,
    required String transactionType,
    required Decimal amount,
    String? categoryId,
    String? description,
    String? notes,
    String? transactionDate,
    String? transferAccountId,
    String? clientId,
    String currency = 'COP',
  }) async {
    final body = _buildBody(
      accountId: accountId,
      transactionType: transactionType,
      amount: amount,
      currency: currency,
      categoryId: categoryId,
      description: description,
      notes: notes,
      transactionDate: transactionDate,
      transferAccountId: transferAccountId,
      clientId: clientId,
    );
    final res = await _dio.post('/transactions', data: body);
    return Transaction.fromJson(res.data as Map<String, dynamic>);
  }

  /// Lists transactions for the active tracking period (default) or a given
  /// [trackingPeriodId].
  Future<List<Transaction>> list({String? trackingPeriodId}) async {
    final res = await _dio.get(
      '/transactions',
      queryParameters: trackingPeriodId != null
          ? {'tracking_period_id': trackingPeriodId}
          : null,
    );
    final items = (res.data as Map<String, dynamic>)['transactions'] as List;
    return items
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a single transaction by [id]. Returns null if 404.
  Future<Transaction?> get(String id) async {
    try {
      final res = await _dio.get('/transactions/$id');
      return Transaction.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Updates an existing transaction (PUT /transactions/:id).
  /// All mutable fields mirror the create call per the contract.
  Future<Transaction> update(
    String id, {
    required String accountId,
    required String transactionType,
    required Decimal amount,
    String? categoryId,
    String? description,
    String? notes,
    String? transactionDate,
    String? transferAccountId,
    String? clientId,
    String currency = 'COP',
  }) async {
    final body = _buildBody(
      accountId: accountId,
      transactionType: transactionType,
      amount: amount,
      currency: currency,
      categoryId: categoryId,
      description: description,
      notes: notes,
      transactionDate: transactionDate,
      transferAccountId: transferAccountId,
      clientId: clientId,
    );
    final res = await _dio.put('/transactions/$id', data: body);
    return Transaction.fromJson(res.data as Map<String, dynamic>);
  }

  /// Soft-deletes a transaction (DELETE /transactions/:id).
  /// The backend reverts the account balance automatically.
  Future<void> delete(String id) async {
    await _dio.delete('/transactions/$id');
  }
}
