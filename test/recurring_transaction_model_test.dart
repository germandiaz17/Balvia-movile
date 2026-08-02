/// Tests for the RecurringTransaction model and the client-side form
/// validation that mirrors services.validateRecurringInput.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/recurring_transaction.dart';

void main() {
  Map<String, dynamic> rowJson({
    String frequency = 'monthly',
    int? dayOfMonth = 5,
    int? dayOfWeek,
    int? customIntervalDays,
    String? nextDueDate = '2026-08-05',
    bool includeNextDueDate = true,
    String? endDate = '2027-01-05',
    bool isActive = true,
    String transactionType = 'expense',
  }) => <String, dynamic>{
    'id': 'rec-1',
    'account_id': 'acc-1',
    'category_id': 'cat-1',
    'name': 'Arriendo',
    'transaction_type': transactionType,
    'amount': '1500000.00',
    'currency': 'COP',
    'description': null,
    'frequency': frequency,
    'custom_interval_days': customIntervalDays,
    'day_of_month': dayOfMonth,
    'day_of_week': dayOfWeek,
    'start_date': '2026-01-05',
    'end_date': endDate,
    if (includeNextDueDate) 'next_due_date': nextDueDate,
    'is_active': isActive,
  };

  group('fromJson', () {
    test('parses a monthly template', () {
      final r = RecurringTransaction.fromJson(rowJson());

      expect(r.id, 'rec-1');
      expect(r.accountId, 'acc-1');
      expect(r.categoryId, 'cat-1');
      expect(r.name, 'Arriendo');
      expect(r.transactionType, 'expense');
      expect(r.amount, Decimal.parse('1500000.00'));
      expect(r.frequency, 'monthly');
      expect(r.dayOfMonth, 5);
      expect(r.startDate, DateTime(2026, 1, 5));
      expect(r.endDate, DateTime(2027, 1, 5));
      expect(r.nextDueDate, DateTime(2026, 8, 5));
      expect(r.isActive, isTrue);
      expect(r.isFinished, isFalse);
    });

    test('an absent next_due_date means the template is finished', () {
      // omitempty: once the engine exhausts a template the key is gone.
      final r = RecurringTransaction.fromJson(
        rowJson(includeNextDueDate: false, isActive: false),
      );

      expect(r.nextDueDate, isNull);
      expect(r.isFinished, isTrue);
      expect(r.nextDueLabel, 'Finalizada');
    });

    test('an explicit null next_due_date behaves the same', () {
      final r = RecurringTransaction.fromJson(rowJson(nextDueDate: null));
      expect(r.nextDueDate, isNull);
      expect(r.isFinished, isTrue);
    });

    test('a null end_date means it runs forever', () {
      final r = RecurringTransaction.fromJson(rowJson(endDate: null));
      expect(r.endDate, isNull);
    });

    test('day_of_week 0 is Sunday, not "unset"', () {
      final r = RecurringTransaction.fromJson(
        rowJson(frequency: 'weekly', dayOfMonth: null, dayOfWeek: 0),
      );
      expect(r.dayOfWeek, 0);
      expect(r.scheduleLabel, 'Semanal · domingo');
    });

    test('parses a custom-interval template', () {
      final r = RecurringTransaction.fromJson(
        rowJson(frequency: 'custom', dayOfMonth: null, customIntervalDays: 10),
      );
      expect(r.customIntervalDays, 10);
      expect(r.scheduleLabel, 'Cada 10 días');
    });

    test('income templates are not expenses', () {
      final r = RecurringTransaction.fromJson(
        rowJson(transactionType: 'income'),
      );
      expect(r.isExpense, isFalse);
    });
  });

  group('toJson', () {
    test('amount is a string and dates are YYYY-MM-DD', () {
      final json = RecurringTransaction.fromJson(rowJson()).toJson();
      expect(json['amount'], '1500000.00');
      expect(json['start_date'], '2026-01-05');
      expect(json['end_date'], '2027-01-05');
      expect(json['next_due_date'], '2026-08-05');
    });

    test('null dates serialise as null', () {
      final json = RecurringTransaction.fromJson(
        rowJson(endDate: null, includeNextDueDate: false),
      ).toJson();
      expect(json['end_date'], isNull);
      expect(json['next_due_date'], isNull);
    });
  });

  group('labels', () {
    test('nextDueLabel reflects the three states', () {
      final live = RecurringTransaction.fromJson(rowJson());
      expect(live.nextDueLabel, 'Próximo: 5 ago');

      final paused = RecurringTransaction.fromJson(rowJson(isActive: false));
      expect(paused.nextDueLabel, 'Pausada');

      final finished = RecurringTransaction.fromJson(
        rowJson(includeNextDueDate: false),
      );
      expect(finished.nextDueLabel, 'Finalizada');
    });

    test('scheduleLabel falls back to the plain frequency', () {
      final daily = RecurringTransaction.fromJson(
        rowJson(frequency: 'daily', dayOfMonth: null),
      );
      expect(daily.scheduleLabel, 'Diaria');

      final yearly = RecurringTransaction.fromJson(
        rowJson(frequency: 'yearly', dayOfMonth: null),
      );
      expect(yearly.scheduleLabel, 'Anual');
    });

    test('frequencyLabel covers every accepted frequency', () {
      expect(kRecurringFrequencies, hasLength(6));
      for (final f in kRecurringFrequencies) {
        expect(frequencyLabel(f), isNot(f), reason: '$f has no Spanish label');
      }
    });

    test('dayOfWeekLabel maps 0-6 following EXTRACT(DOW)', () {
      expect(dayOfWeekLabel(0), 'Domingo');
      expect(dayOfWeekLabel(1), 'Lunes');
      expect(dayOfWeekLabel(6), 'Sábado');
    });

    test('transfer is not an accepted template type', () {
      expect(kRecurringTypes, ['income', 'expense']);
      expect(kRecurringTypes.contains('transfer'), isFalse);
    });
  });

  group('validateRecurringForm', () {
    String? validate({
      String name = 'Arriendo',
      String? accountId = 'acc-1',
      String transactionType = 'expense',
      Decimal? amount,
      String frequency = 'monthly',
      int? customIntervalDays,
      int? dayOfMonth = 5,
      int? dayOfWeek,
      DateTime? startDate,
      DateTime? endDate,
    }) => validateRecurringForm(
      name: name,
      accountId: accountId,
      transactionType: transactionType,
      amount: amount ?? Decimal.parse('1500000'),
      frequency: frequency,
      customIntervalDays: customIntervalDays,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      startDate: startDate ?? DateTime(2026, 1, 5),
      endDate: endDate,
    );

    test('accepts a well-formed monthly template', () {
      expect(validate(), isNull);
    });

    test('rejects an empty or blank name', () {
      expect(validate(name: ''), isNotNull);
      expect(validate(name: '   '), isNotNull);
    });

    test('rejects a missing account', () {
      expect(validate(accountId: null), 'Selecciona una cuenta');
    });

    test('rejects transfer, which templates do not support', () {
      expect(validate(transactionType: 'transfer'), isNotNull);
    });

    test('rejects a zero or negative amount', () {
      expect(validate(amount: Decimal.zero), isNotNull);
      expect(validate(amount: Decimal.parse('-100')), isNotNull);
    });

    test('rejects an unknown frequency', () {
      expect(validate(frequency: 'fortnightly'), 'Frecuencia inválida');
    });

    test('custom requires a positive interval', () {
      expect(validate(frequency: 'custom', dayOfMonth: null), isNotNull);
      expect(
        validate(frequency: 'custom', dayOfMonth: null, customIntervalDays: 0),
        isNotNull,
      );
      expect(
        validate(frequency: 'custom', dayOfMonth: null, customIntervalDays: 10),
        isNull,
      );
    });

    test('day_of_month must be 1-31', () {
      expect(validate(dayOfMonth: 0), isNotNull);
      expect(validate(dayOfMonth: 32), isNotNull);
      expect(validate(dayOfMonth: 1), isNull);
      expect(validate(dayOfMonth: 31), isNull);
    });

    test('day_of_week must be 0-6, and 0 is valid', () {
      expect(
        validate(frequency: 'weekly', dayOfMonth: null, dayOfWeek: 0),
        isNull,
      );
      expect(
        validate(frequency: 'weekly', dayOfMonth: null, dayOfWeek: 6),
        isNull,
      );
      expect(
        validate(frequency: 'weekly', dayOfMonth: null, dayOfWeek: 7),
        isNotNull,
      );
      expect(
        validate(frequency: 'weekly', dayOfMonth: null, dayOfWeek: -1),
        isNotNull,
      );
    });

    test('end_date must be strictly after start_date', () {
      final start = DateTime(2026, 1, 5);
      expect(validate(startDate: start, endDate: start), isNotNull);
      expect(
        validate(startDate: start, endDate: DateTime(2026, 1, 4)),
        isNotNull,
      );
      expect(validate(startDate: start, endDate: DateTime(2026, 1, 6)), isNull);
    });

    test('a null end_date is fine', () {
      expect(validate(endDate: null), isNull);
    });
  });

  group('shortDate', () {
    test('renders day and abbreviated month in Spanish', () {
      expect(shortDate(DateTime(2026, 8, 5)), '5 ago');
      expect(shortDate(DateTime(2026, 1, 31)), '31 ene');
      expect(shortDate(DateTime(2026, 12, 1)), '1 dic');
    });
  });
}
