import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/account.dart';

void main() {
  test('Account.fromJson parses money as Decimal', () {
    final a = Account.fromJson({
      'id': 'abc',
      'name': 'Efectivo',
      'account_type': 'cash',
      'currency': 'COP',
      'current_balance': '95000.00',
      'is_archived': false,
      'icon': null,
      'color': null,
    });
    expect(a.name, 'Efectivo');
    expect(a.currentBalance, Decimal.parse('95000.00'));
    expect(a.currency, 'COP');
    expect(a.isArchived, isFalse);
  });

  test('Account.fromJson defaults isArchived to false when field absent', () {
    final a = Account.fromJson({
      'id': 'def',
      'name': 'Ahorros',
      'account_type': 'savings',
      'currency': 'COP',
      'current_balance': '2450000.00',
      'icon': null,
      'color': null,
      // is_archived intentionally absent
    });
    expect(a.isArchived, isFalse);
  });

  test('Account.fromJson parses is_archived true', () {
    final a = Account.fromJson({
      'id': 'ghi',
      'name': 'Cuenta cerrada',
      'account_type': 'checking',
      'currency': 'COP',
      'current_balance': '0.00',
      'is_archived': true,
      'icon': null,
      'color': null,
    });
    expect(a.isArchived, isTrue);
  });

  test('Account.fromJson parses color and icon when present', () {
    final a = Account.fromJson({
      'id': 'jkl',
      'name': 'Nequi',
      'account_type': 'savings',
      'currency': 'COP',
      'current_balance': '89500.00',
      'is_archived': false,
      'icon': 'wallet',
      'color': '#AB47BC',
    });
    expect(a.color, '#AB47BC');
    expect(a.icon, 'wallet');
  });
}
