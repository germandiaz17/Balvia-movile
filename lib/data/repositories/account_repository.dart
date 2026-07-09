import 'package:dio/dio.dart';

import '../models/account.dart';

/// CRUD for accounts (only list + create are used in the first slice).
class AccountRepository {
  AccountRepository(this._dio);

  final Dio _dio;

  Future<List<Account>> list() async {
    final res = await _dio.get('/accounts');
    final items = (res.data as Map<String, dynamic>)['accounts'] as List;
    return items
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Account> create({
    required String name,
    required String accountType,
    required String initialBalance,
  }) async {
    final res = await _dio.post(
      '/accounts',
      data: {
        'name': name,
        'account_type': accountType,
        'initial_balance': initialBalance,
      },
    );
    return Account.fromJson(res.data as Map<String, dynamic>);
  }
}
