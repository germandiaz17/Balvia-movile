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
      'icon': null,
      'color': null,
    });
    expect(a.name, 'Efectivo');
    expect(a.currentBalance, Decimal.parse('95000.00'));
    expect(a.currency, 'COP');
  });
}
