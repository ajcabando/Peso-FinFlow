import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'wasm/database_connection_web_stub.dart'
    if (dart.library.js_interop) 'wasm/database_connection_web.dart';

/// Opens the FinFlow database connection for the current platform.
///
/// - **Android / iOS / desktop**: native SQLite bundled via `drift_flutter`
///   (sqlite3 native assets).
/// - **Web**: the SQLite WASM build shipped in `web/` (`sqlite3.wasm` and
///   `drift_worker.js`), persisted through the browser's File System API.
///
/// The `package:drift/wasm.dart` import is deliberately behind a conditional
/// import: `dart:js_interop` only exists on the web, so the VM / test runner
/// never compiles it.
///
/// The connection is deliberately *lazy*: the database file is only opened on
/// first use, keeping cold start fast.
DatabaseConnection openDatabaseConnection() {
  if (kIsWeb) {
    return openWebDatabaseConnection(AppConstants.databaseName);
  }
  return driftDatabase(name: AppConstants.databaseName);
}
