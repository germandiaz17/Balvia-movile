// Drift database connection helper for the overlay isolate.
//
// ARCHITECTURE DECISION (2026-07-10):
//   The overlay runs in a separate FlutterEngine/isolate and cannot share the
//   main app's Drift connection or Riverpod providers. Instead, we open a
//   dedicated NativeDatabase connection to the SAME SQLite file that the main
//   app uses (balvia.sqlite). SQLite with WAL journal mode supports concurrent
//   readers and one writer without blocking — the overlay is the sole writer
//   in its isolate, while the main app reads/writes in its own connection.
//
//   WAL is enabled via the `setup` callback (PRAGMA journal_mode=WAL) and a
//   busy_timeout is set so concurrent writes degrade gracefully instead of
//   immediately returning SQLITE_BUSY.
//
//   The overlay connection is opened once when the overlay engine starts and
//   closed when the overlay is dismissed (FlutterEngine teardown).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/app_database.dart';

/// Opens the same SQLite file used by the main app but with WAL enabled.
/// Safe to open from the overlay isolate concurrently with the main app.
Future<AppDatabase> openOverlayDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'balvia.sqlite'));

  final db = AppDatabase(
    NativeDatabase(
      file,
      setup: (rawDb) {
        // Enable WAL for concurrent multi-connection access.
        rawDb.execute('PRAGMA journal_mode=WAL;');
        // Wait up to 3 s when another writer holds the lock.
        rawDb.execute('PRAGMA busy_timeout=3000;');
      },
    ),
  );
  return db;
}
