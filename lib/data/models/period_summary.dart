import 'package:decimal/decimal.dart';

/// A single time sub-block within a period (used by biweekly and weekly views).
/// Mirrors sub_periods elements in docs/API_CONTRACT.md §Tracking periods.
class SubPeriod {
  const SubPeriod({
    required this.index,
    required this.from,
    required this.to,
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalTransfers,
    required this.netSavings,
    required this.savingsRate,
    required this.transactionCount,
    required this.expenseTransactionCount,
    required this.incomeTransactionCount,
  });

  final int index;

  /// YYYY-MM-DD
  final String from;

  /// YYYY-MM-DD
  final String to;

  final Decimal totalIncome;
  final Decimal totalExpenses;
  final Decimal totalTransfers;
  final Decimal netSavings;

  /// Percentage 0–100, 2 decimal places.
  final Decimal savingsRate;

  final int transactionCount;
  final int expenseTransactionCount;
  final int incomeTransactionCount;

  /// Whether today falls within this sub-period (for UI highlighting).
  bool get isCurrent {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fromDate = DateTime.parse(from);
    final toDate = DateTime.parse(to);
    return !today.isBefore(fromDate) && !today.isAfter(toDate);
  }

  factory SubPeriod.fromJson(Map<String, dynamic> json) => SubPeriod(
    index: json['index'] as int,
    from: json['from'] as String,
    to: json['to'] as String,
    totalIncome: Decimal.parse(json['total_income'] as String),
    totalExpenses: Decimal.parse(json['total_expenses'] as String),
    totalTransfers: Decimal.parse(json['total_transfers'] as String),
    netSavings: Decimal.parse(json['net_savings'] as String),
    savingsRate: Decimal.parse(json['savings_rate'] as String),
    transactionCount: json['transaction_count'] as int,
    expenseTransactionCount: json['expense_transaction_count'] as int,
    incomeTransactionCount: json['income_transaction_count'] as int,
  );
}

/// Summary of a tracking period for a given view.
/// Mirrors the summary object in docs/API_CONTRACT.md §Tracking periods.
/// All money fields are Decimal (API sends as string).
///
/// The JSONB breakdown fields (expense_by_category, etc.) are only populated
/// for CLOSED periods; for active periods they are omitted by the API (omitempty).
/// This model stores them as nullable lists so the UI can branch accordingly.
class PeriodSummary {
  const PeriodSummary({
    required this.periodId,
    required this.view,
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalTransfers,
    required this.netSavings,
    required this.savingsRate,
    required this.transactionCount,
    required this.expenseTransactionCount,
    required this.incomeTransactionCount,
    this.topExpenseCategoryId,
    this.topExpenseCategoryTotal,
    this.subPeriods,
  });

  final String periodId;

  /// full | biweekly | weekly
  final String view;

  final Decimal totalIncome;
  final Decimal totalExpenses;
  final Decimal totalTransfers;
  final Decimal netSavings;

  /// Percentage 0–100, 2 decimal places.
  final Decimal savingsRate;

  final int transactionCount;
  final int expenseTransactionCount;
  final int incomeTransactionCount;

  final String? topExpenseCategoryId;
  final Decimal? topExpenseCategoryTotal;

  /// Non-null only for biweekly and weekly views.
  final List<SubPeriod>? subPeriods;

  factory PeriodSummary.fromJson(Map<String, dynamic> json) {
    // sub_periods can be null (full view or active period with no sub_periods).
    final rawSubs = json['sub_periods'];
    final subPeriods = rawSubs is List
        ? rawSubs
              .map((e) => SubPeriod.fromJson(e as Map<String, dynamic>))
              .toList()
        : null;

    // top_expense_category_total is a nullable string in the API.
    final topTotal = json['top_expense_category_total'];
    final topExpenseCategoryTotal = topTotal != null
        ? Decimal.parse(topTotal as String)
        : null;

    return PeriodSummary(
      periodId: json['period_id'] as String,
      view: json['view'] as String,
      totalIncome: Decimal.parse(json['total_income'] as String),
      totalExpenses: Decimal.parse(json['total_expenses'] as String),
      totalTransfers: Decimal.parse(json['total_transfers'] as String),
      netSavings: Decimal.parse(json['net_savings'] as String),
      savingsRate: Decimal.parse(json['savings_rate'] as String),
      transactionCount: json['transaction_count'] as int,
      expenseTransactionCount: json['expense_transaction_count'] as int,
      incomeTransactionCount: json['income_transaction_count'] as int,
      topExpenseCategoryId: json['top_expense_category_id'] as String?,
      topExpenseCategoryTotal: topExpenseCategoryTotal,
      subPeriods: subPeriods,
    );
  }
}
