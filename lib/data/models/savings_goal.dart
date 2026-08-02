import 'package:decimal/decimal.dart';

/// Status values accepted by the backend (services.ValidGoalStatuses).
const kGoalStatuses = <String>['active', 'achieved', 'abandoned', 'paused'];

/// Spanish labels for the status chip.
String goalStatusLabel(String status) => switch (status) {
  'active' => 'Activa',
  'achieved' => 'Lograda',
  'abandoned' => 'Abandonada',
  'paused' => 'Pausada',
  _ => status,
};

/// A savings goal. Mirrors `goalResponse` in the backend's
/// internal/handlers/savings_goal.go.
///
/// [currentAmount] is maintained server-side: contributions are applied inside
/// `CreateContributionTx`, which also flips the status to `achieved`. The client
/// never computes it.
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.currency,
    required this.startDate,
    required this.targetDate,
    required this.status,
    this.description,
    this.icon,
    this.color,
    this.linkedAccountId,
    this.achievedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final Decimal targetAmount;
  final Decimal currentAmount;
  final String currency;
  final DateTime startDate;
  final DateTime targetDate;
  final String status;
  final String? linkedAccountId;
  final DateTime? achievedAt;

  /// Progress as a 0–1 fraction, clamped. A zero target reads as 0 rather than
  /// dividing by zero.
  double get progressFraction {
    if (targetAmount <= Decimal.zero) return 0;
    final raw = (currentAmount / targetAmount).toDouble();
    return raw.clamp(0.0, 1.0);
  }

  /// Progress as a percentage, NOT clamped — overshooting a goal is worth
  /// showing ("120%").
  double get progressPercent {
    if (targetAmount <= Decimal.zero) return 0;
    return (currentAmount / targetAmount).toDouble() * 100.0;
  }

  /// Whole days from today until [targetDate]. Negative once overdue.
  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    return target.difference(today).inDays;
  }

  bool get isAchieved => status == 'achieved';

  /// Whether the target date has passed without the goal being met.
  bool get isOverdue => !isAchieved && daysRemaining < 0;

  /// What is still missing to reach the target. Never negative.
  Decimal get remainingAmount {
    final diff = targetAmount - currentAmount;
    return diff < Decimal.zero ? Decimal.zero : diff;
  }

  factory SavingsGoal.fromJson(Map<String, dynamic> json) => SavingsGoal(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    icon: json['icon'] as String?,
    color: json['color'] as String?,
    targetAmount: Decimal.parse(json['target_amount'] as String),
    currentAmount: Decimal.parse(json['current_amount'] as String),
    currency: json['currency'] as String? ?? 'COP',
    startDate: DateTime.parse(json['start_date'] as String),
    targetDate: DateTime.parse(json['target_date'] as String),
    status: json['status'] as String,
    linkedAccountId: json['linked_account_id'] as String?,
    achievedAt: json['achieved_at'] == null
        ? null
        : DateTime.parse(json['achieved_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'target_amount': targetAmount.toStringAsFixed(2),
    'current_amount': currentAmount.toStringAsFixed(2),
    'currency': currency,
    'start_date': formatDateOnly(startDate),
    'target_date': formatDateOnly(targetDate),
    'status': status,
    'linked_account_id': linkedAccountId,
    'achieved_at': achievedAt?.toUtc().toIso8601String(),
  };

  SavingsGoal copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    String? color,
    Decimal? targetAmount,
    Decimal? currentAmount,
    String? currency,
    DateTime? startDate,
    DateTime? targetDate,
    String? status,
    String? linkedAccountId,
    DateTime? achievedAt,
  }) => SavingsGoal(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    targetAmount: targetAmount ?? this.targetAmount,
    currentAmount: currentAmount ?? this.currentAmount,
    currency: currency ?? this.currency,
    startDate: startDate ?? this.startDate,
    targetDate: targetDate ?? this.targetDate,
    status: status ?? this.status,
    linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    achievedAt: achievedAt ?? this.achievedAt,
  );
}

/// A single contribution to a savings goal. Mirrors `contributionResponse`.
class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.savingsGoalId,
    required this.trackingPeriodId,
    required this.amount,
    required this.contributionDate,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String savingsGoalId;
  final String trackingPeriodId;
  final Decimal amount;
  final DateTime contributionDate;
  final String? notes;
  final DateTime createdAt;

  factory GoalContribution.fromJson(Map<String, dynamic> json) =>
      GoalContribution(
        id: json['id'] as String,
        savingsGoalId: json['savings_goal_id'] as String,
        trackingPeriodId: json['tracking_period_id'] as String,
        amount: Decimal.parse(json['amount'] as String),
        contributionDate: DateTime.parse(json['contribution_date'] as String),
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'savings_goal_id': savingsGoalId,
    'tracking_period_id': trackingPeriodId,
    'amount': amount.toStringAsFixed(2),
    'contribution_date': formatDateOnly(contributionDate),
    'notes': notes,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

/// Formats a [DateTime] as the YYYY-MM-DD the API expects for date-only fields.
String formatDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
