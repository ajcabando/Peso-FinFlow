/// Canonical operation-log conflict resolution — a pure Dart port of the
/// server rules (`server/src/sync/lww.ts`, docs/BACKEND_API.md §4). Pure and
/// deterministic so the server and every client converge on the same winner:
///
///   1. `base_version` CAS mismatch → the incoming op is stale and must be
///      re-based (the caller re-pulls and recomputes from `current.version`).
///   2. Highest `version` wins.
///   3. Version equal → newest `updated_at` wins.
///   4. Still equal → lexicographically smallest `opId` wins.
library;

/// A candidate for the last-write-wins comparison.
class LwwCandidate {
  const LwwCandidate({required this.version, required this.updatedAt, required this.opId});

  final int version;
  final DateTime updatedAt;
  final String opId;
}

enum LwwWinner { current, incoming }

/// LWW comparison — the winner between the stored (`current`) state and a
/// competing (`incoming`) write. Callers must first check the CAS guard
/// (`incoming.baseVersion <= current.version`) separately.
LwwWinner lwwWinner(LwwCandidate current, LwwCandidate incoming) {
  if (incoming.version > current.version) return LwwWinner.incoming;
  if (incoming.version < current.version) return LwwWinner.current;
  if (incoming.updatedAt.isAfter(current.updatedAt)) return LwwWinner.incoming;
  if (incoming.updatedAt.isBefore(current.updatedAt)) return LwwWinner.current;
  // Tie-break: smallest opId wins (both UUIDs — stable string compare).
  return incoming.opId.compareTo(current.opId) < 0
      ? LwwWinner.incoming
      : LwwWinner.current;
}

/// CAS guard: an op whose `baseVersion` exceeds the stored version was based
/// on a state that no longer exists — it must be re-based (not applied).
bool isCasStale({required int baseVersion, required int currentVersion}) =>
    baseVersion > currentVersion;
