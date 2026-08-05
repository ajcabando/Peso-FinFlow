import 'package:uuid/uuid.dart';

/// Generates UUIDv4 identifiers for every entity persisted locally.
///
/// UUIDs (instead of auto-incrementing integers) keep the data model
/// portable: they never collide across devices, exports, imports or a
/// future cloud sync module.
abstract final class IdGenerator {
  static const Uuid _uuid = Uuid();

  /// Returns a new random UUIDv4 string.
  static String next() => _uuid.v4();
}
