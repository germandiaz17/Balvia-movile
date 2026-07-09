import 'package:decimal/decimal.dart';

/// A financial transaction. Money fields use Decimal; the API sends them as
/// strings. Mirrors the contract object in docs/API_CONTRACT.md §Transactions.
class Transaction {
  const Transaction({
    required this.id,
    required this.trackingPeriodId,
    required this.accountId,
    required this.transactionType,
    required this.amount,
    required this.currency,
    required this.transactionDate,
    required this.createdAt,
    this.categoryId,
    this.description,
    this.notes,
    this.transferAccountId,
    this.clientId,
    this.recurringTransactionId,
    this.occurrenceDate,
  });

  final String id;
  final String trackingPeriodId;
  final String accountId;

  /// income | expense | transfer
  final String transactionType;
  final Decimal amount;
  final String currency;
  final String? categoryId;
  final String? description;
  final String? notes;

  /// YYYY-MM-DD
  final String transactionDate;
  final String? transferAccountId;
  final String? clientId;

  // Server-managed recurring fields (read-only, may be null).
  final String? recurringTransactionId;
  final String? occurrenceDate;
  final DateTime createdAt;

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'] as String,
    trackingPeriodId: json['tracking_period_id'] as String,
    accountId: json['account_id'] as String,
    transactionType: json['transaction_type'] as String,
    amount: Decimal.parse(json['amount'] as String),
    currency: json['currency'] as String,
    categoryId: json['category_id'] as String?,
    description: json['description'] as String?,
    notes: json['notes'] as String?,
    transactionDate: json['transaction_date'] as String,
    transferAccountId: json['transfer_account_id'] as String?,
    clientId: json['client_id'] as String?,
    recurringTransactionId: json['recurring_transaction_id'] as String?,
    occurrenceDate: json['occurrence_date'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'tracking_period_id': trackingPeriodId,
    'account_id': accountId,
    'transaction_type': transactionType,
    'amount': amount.toStringAsFixed(2),
    'currency': currency,
    'category_id': categoryId,
    'description': description,
    'notes': notes,
    'transaction_date': transactionDate,
    'transfer_account_id': transferAccountId,
    'client_id': clientId,
    'recurring_transaction_id': recurringTransactionId,
    'occurrence_date': occurrenceDate,
    'created_at': createdAt.toIso8601String(),
  };
}
