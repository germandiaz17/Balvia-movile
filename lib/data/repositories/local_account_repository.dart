// Local account repository backed by Drift (offline-first reads).
//
// Writes still go through the network API (accounts are mutated online per v1
// design; they are pulled into Drift by the sync engine). This repository
// provides offline-first reads only.

import 'package:decimal/decimal.dart';

import '../local/app_database.dart' as db;
import '../../data/models/account.dart';

/// Converts a Drift [db.Account] row to the domain [Account].
Account _accountRowToModel(db.Account row) => Account(
  id: row.id,
  name: row.name,
  accountType: row.accountType,
  currency: row.currency,
  currentBalance: Decimal.parse(row.currentBalance),
  icon: row.icon,
  color: row.color,
);

class LocalAccountRepository {
  LocalAccountRepository(this._db);

  final db.AppDatabase _db;

  /// Stream of all non-archived, non-deleted accounts (offline-first).
  Stream<List<Account>> watchAll() => _db.accountsDao.watchAll().map(
    (rows) => rows.map(_accountRowToModel).toList(),
  );

  /// One-shot list of accounts.
  Future<List<Account>> getAll() async {
    final rows = await _db.accountsDao.getAll();
    return rows.map(_accountRowToModel).toList();
  }
}
