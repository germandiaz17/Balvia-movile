import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../models/transaction.dart';

/// Handles transaction API calls. Amount is Decimal on the client; it is
/// serialised as a string ("12000.00") for the backend — never a double.
class TransactionRepository {
  TransactionRepository(this._dio);

  final Dio _dio;

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
}
