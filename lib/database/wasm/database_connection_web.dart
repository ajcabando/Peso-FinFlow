import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Opens the SQLite WASM database on the web.
///
/// Compiled only when `dart.library.js_interop` is available (web targets);
/// the non-web stub in this directory is used everywhere else.
DatabaseConnection openWebDatabaseConnection(String databaseName) {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: databaseName,
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
