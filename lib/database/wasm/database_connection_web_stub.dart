import 'package:drift/drift.dart';

/// Non-web fallback for [openWebDatabaseConnection]. This file is only used
/// when `dart.library.js_interop` is unavailable (VM, native targets), where
/// the WASM database can never run — native platforms use `drift_flutter`.
DatabaseConnection openWebDatabaseConnection(String databaseName) {
  throw UnsupportedError(
    'The WASM database connection is only available on the web. '
    'Native platforms use the drift_flutter connection.',
  );
}
