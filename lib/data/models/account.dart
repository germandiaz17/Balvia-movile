import 'package:decimal/decimal.dart';

/// Financial account. Money fields are Decimal (never double); the API sends
/// them as strings.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currency,
    required this.currentBalance,
    required this.isArchived,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final String accountType;
  final String currency;
  final Decimal currentBalance;
  final bool isArchived;
  final String? icon;
  final String? color;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    accountType: json['account_type'] as String,
    currency: json['currency'] as String,
    currentBalance: Decimal.parse(json['current_balance'] as String),
    isArchived: json['is_archived'] as bool? ?? false,
    icon: json['icon'] as String?,
    color: json['color'] as String?,
  );
}
