import 'package:decimal/decimal.dart';

/// A budget tied to the active tracking period.
/// Mirrors the contract object in docs/API_CONTRACT.md §Budgets.
///
/// [categoryId] null → global budget for the period.
/// [alertThresholdWarning] / [alertThresholdCritical] are percentages (0–100).
class Budget {
  const Budget({
    required this.id,
    required this.trackingPeriodId,
    required this.amount,
    required this.currency,
    required this.alertThresholdWarning,
    required this.alertThresholdCritical,
    this.categoryId,
    this.notes,
  });

  final String id;
  final String trackingPeriodId;
  final String? categoryId;
  final Decimal amount;
  final String currency;

  /// Percentage at which the warning color triggers (default 80).
  final Decimal alertThresholdWarning;

  /// Percentage at which the critical / exceeded color triggers (default 100).
  final Decimal alertThresholdCritical;
  final String? notes;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'] as String,
    trackingPeriodId: json['tracking_period_id'] as String,
    categoryId: json['category_id'] as String?,
    amount: Decimal.parse(json['amount'] as String),
    currency: json['currency'] as String? ?? 'COP',
    alertThresholdWarning: Decimal.parse(
      json['alert_threshold_warning'] as String? ?? '80',
    ),
    alertThresholdCritical: Decimal.parse(
      json['alert_threshold_critical'] as String? ?? '100',
    ),
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'tracking_period_id': trackingPeriodId,
    'category_id': categoryId,
    'amount': amount.toStringAsFixed(2),
    'currency': currency,
    'alert_threshold_warning': alertThresholdWarning.toStringAsFixed(2),
    'alert_threshold_critical': alertThresholdCritical.toStringAsFixed(2),
    'notes': notes,
  };

  Budget copyWith({
    String? id,
    String? trackingPeriodId,
    String? categoryId,
    Decimal? amount,
    String? currency,
    Decimal? alertThresholdWarning,
    Decimal? alertThresholdCritical,
    String? notes,
  }) => Budget(
    id: id ?? this.id,
    trackingPeriodId: trackingPeriodId ?? this.trackingPeriodId,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    currency: currency ?? this.currency,
    alertThresholdWarning: alertThresholdWarning ?? this.alertThresholdWarning,
    alertThresholdCritical:
        alertThresholdCritical ?? this.alertThresholdCritical,
    notes: notes ?? this.notes,
  );
}
