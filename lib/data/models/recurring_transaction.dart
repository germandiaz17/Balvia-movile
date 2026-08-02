import 'package:decimal/decimal.dart';

import 'savings_goal.dart' show formatDateOnly;

/// Frequencies the backend accepts (services.validFrequencies).
const kRecurringFrequencies = <String>[
  'daily',
  'weekly',
  'biweekly',
  'monthly',
  'yearly',
  'custom',
];

/// Transaction types a template may have. `transfer` is deliberately excluded —
/// recurring transfers are not part of the domain model
/// (services.validRecurringTypes).
const kRecurringTypes = <String>['income', 'expense'];

String frequencyLabel(String frequency) => switch (frequency) {
  'daily' => 'Diaria',
  'weekly' => 'Semanal',
  'biweekly' => 'Quincenal',
  'monthly' => 'Mensual',
  'yearly' => 'Anual',
  'custom' => 'Personalizada',
  _ => frequency,
};

/// day_of_week follows Postgres EXTRACT(DOW): 0 = Sunday … 6 = Saturday.
/// Careful: 0 is a real value, not "unset".
String dayOfWeekLabel(int dayOfWeek) => switch (dayOfWeek) {
  0 => 'Domingo',
  1 => 'Lunes',
  2 => 'Martes',
  3 => 'Miércoles',
  4 => 'Jueves',
  5 => 'Viernes',
  6 => 'Sábado',
  _ => 'Día $dayOfWeek',
};

const _monthAbbr = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Short date for the cards: "5 ago".
String shortDate(DateTime d) => '${d.day} ${_monthAbbr[d.month - 1]}';

/// A recurring transaction template. Mirrors `recurringResponse` in
/// internal/handlers/recurring_transaction.go.
///
/// The client never materialises occurrences or computes the next date: the
/// backend engine owns both. [nextDueDate] is read-only here.
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.accountId,
    required this.name,
    required this.transactionType,
    required this.amount,
    required this.currency,
    required this.frequency,
    required this.startDate,
    required this.isActive,
    this.categoryId,
    this.description,
    this.customIntervalDays,
    this.dayOfMonth,
    this.dayOfWeek,
    this.endDate,
    this.nextDueDate,
  });

  final String id;
  final String accountId;
  final String? categoryId;
  final String name;
  final String transactionType;
  final Decimal amount;
  final String currency;
  final String? description;
  final String frequency;
  final int? customIntervalDays;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final DateTime startDate;
  final DateTime? endDate;

  /// Null once the engine has run the template past its end_date.
  final DateTime? nextDueDate;
  final bool isActive;

  bool get isExpense => transactionType == 'expense';

  /// A template is finished when the engine has no next occurrence left for it.
  bool get isFinished => nextDueDate == null;

  /// What the card shows under the name.
  String get nextDueLabel {
    if (isFinished) return 'Finalizada';
    if (!isActive) return 'Pausada';
    return 'Próximo: ${shortDate(nextDueDate!)}';
  }

  /// "Mensual · día 5", "Semanal · lunes", "Cada 10 días".
  String get scheduleLabel => switch (frequency) {
    'monthly' when dayOfMonth != null =>
      '${frequencyLabel(frequency)} · día $dayOfMonth',
    'weekly' || 'biweekly' when dayOfWeek != null =>
      '${frequencyLabel(frequency)} · ${dayOfWeekLabel(dayOfWeek!).toLowerCase()}',
    'custom' when customIntervalDays != null => 'Cada $customIntervalDays días',
    _ => frequencyLabel(frequency),
  };

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) =>
      RecurringTransaction(
        id: json['id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String?,
        name: json['name'] as String,
        transactionType: json['transaction_type'] as String,
        amount: Decimal.parse(json['amount'] as String),
        currency: json['currency'] as String? ?? 'COP',
        description: json['description'] as String?,
        frequency: json['frequency'] as String,
        customIntervalDays: json['custom_interval_days'] as int?,
        dayOfMonth: json['day_of_month'] as int?,
        dayOfWeek: json['day_of_week'] as int?,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: json['end_date'] == null
            ? null
            : DateTime.parse(json['end_date'] as String),
        // Absent (omitempty) or null once the template is exhausted.
        nextDueDate: json['next_due_date'] == null
            ? null
            : DateTime.parse(json['next_due_date'] as String),
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'account_id': accountId,
    'category_id': categoryId,
    'name': name,
    'transaction_type': transactionType,
    'amount': amount.toStringAsFixed(2),
    'currency': currency,
    'description': description,
    'frequency': frequency,
    'custom_interval_days': customIntervalDays,
    'day_of_month': dayOfMonth,
    'day_of_week': dayOfWeek,
    'start_date': formatDateOnly(startDate),
    'end_date': endDate == null ? null : formatDateOnly(endDate!),
    'next_due_date': nextDueDate == null ? null : formatDateOnly(nextDueDate!),
    'is_active': isActive,
  };
}

/// Client-side mirror of `validateRecurringInput` so the user finds out about a
/// bad combination before the round trip. Returns null when the form is valid,
/// otherwise a Spanish message.
///
/// Kept as a free function (no widgets involved) so it is directly testable.
String? validateRecurringForm({
  required String name,
  required String? accountId,
  required String transactionType,
  required Decimal? amount,
  required String frequency,
  int? customIntervalDays,
  int? dayOfMonth,
  int? dayOfWeek,
  required DateTime startDate,
  DateTime? endDate,
}) {
  if (name.trim().isEmpty) return 'El nombre es requerido';
  if (accountId == null) return 'Selecciona una cuenta';
  if (!kRecurringTypes.contains(transactionType)) {
    return 'Tipo inválido: solo ingreso o gasto';
  }
  if (amount == null || amount <= Decimal.zero) {
    return 'El monto debe ser mayor a cero';
  }
  if (!kRecurringFrequencies.contains(frequency)) {
    return 'Frecuencia inválida';
  }
  if (frequency == 'custom' &&
      (customIntervalDays == null || customIntervalDays <= 0)) {
    return 'Indica cada cuántos días se repite';
  }
  if (dayOfMonth != null && (dayOfMonth < 1 || dayOfMonth > 31)) {
    return 'El día del mes debe estar entre 1 y 31';
  }
  if (dayOfWeek != null && (dayOfWeek < 0 || dayOfWeek > 6)) {
    return 'Día de la semana inválido';
  }
  if (endDate != null && !endDate.isAfter(startDate)) {
    return 'La fecha de fin debe ser posterior a la de inicio';
  }
  return null;
}
