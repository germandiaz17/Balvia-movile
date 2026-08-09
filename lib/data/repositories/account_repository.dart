import 'package:dio/dio.dart';

import '../models/account.dart';

/// CRUD for accounts. Supports list, create, update, delete (soft).
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
    String? color,
  }) async {
    final res = await _dio.post(
      '/accounts',
      data: {
        'name': name,
        'account_type': accountType,
        'initial_balance': initialBalance,
        'color': color,
      },
    );
    return Account.fromJson(res.data as Map<String, dynamic>);
  }

  /// Full replace, like every PUT in this API — send every field you want kept.
  /// Anything omitted comes back null, so [icon] and [color] must be echoed
  /// from the account being edited even when the user did not touch them.
  ///
  /// [initialBalance] is the one exception: omit it (null) to leave the opening
  /// balance untouched. The backend only accepts it while the account has no
  /// transactions and answers 422 otherwise, since restating the opening
  /// balance of an account with movements would rewrite history.
  Future<Account> update(
    String id, {
    required String name,
    required String accountType,
    String? icon,
    String? color,
    String? initialBalance,
    bool isArchived = false,
  }) async {
    final res = await _dio.put(
      '/accounts/$id',
      data: {
        'name': name,
        'account_type': accountType,
        'icon': icon,
        'color': color,
        'is_archived': isArchived,
        'initial_balance': ?initialBalance,
      },
    );
    return Account.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete('/accounts/$id');
  }
}
