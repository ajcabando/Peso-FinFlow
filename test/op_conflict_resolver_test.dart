import 'package:finflow/features/sync/data/sync/op_conflict_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the pure-Dart port of the server's LWW conflict resolution
/// (`server/src/sync/lww.ts`). Deterministic and antisymmetric so the server
/// and every client converge on the same winner.
void main() {
  DateTime t(String iso) => DateTime.parse(iso);

  LwwCandidate candidate({
    required int version,
    required String updatedAt,
    required String opId,
  }) => LwwCandidate(
    version: version,
    updatedAt: t(updatedAt),
    opId: opId,
  );

  test('highest version wins', () {
    final current = candidate(version: 1, updatedAt: '2026-08-08T10:00:00Z', opId: 'a');
    final incoming = candidate(version: 2, updatedAt: '2026-08-08T09:00:00Z', opId: 'b');
    expect(lwwWinner(current, incoming), LwwWinner.incoming);
    expect(lwwWinner(incoming, current), LwwWinner.current);
  });

  test('version ties break by newest updated_at', () {
    final current = candidate(version: 2, updatedAt: '2026-08-08T10:00:00Z', opId: 'a');
    final incoming = candidate(version: 2, updatedAt: '2026-08-08T11:00:00Z', opId: 'b');
    expect(lwwWinner(current, incoming), LwwWinner.incoming);
    expect(lwwWinner(incoming, current), LwwWinner.current);
  });

  test('full ties break by lexicographically smallest opId', () {
    final current = candidate(version: 2, updatedAt: '2026-08-08T10:00:00Z', opId: '9999');
    final incoming = candidate(version: 2, updatedAt: '2026-08-08T10:00:00Z', opId: '1111');
    expect(lwwWinner(current, incoming), LwwWinner.incoming); // 1111 < 9999
    expect(lwwWinner(incoming, current), LwwWinner.current);
  });

  test('is deterministic and antisymmetric', () {
    final a = candidate(version: 3, updatedAt: '2026-08-08T10:00:00Z', opId: 'a');
    final b = candidate(version: 3, updatedAt: '2026-08-08T10:00:00Z', opId: 'b');
    // a < b lexicographically, so a wins in every arrangement.
    expect(lwwWinner(b, a), LwwWinner.incoming);
    expect(lwwWinner(a, b), LwwWinner.current);
    // Repeatability.
    for (var i = 0; i < 5; i++) {
      expect(lwwWinner(b, a), LwwWinner.incoming);
    }
  });

  test('CAS guard: base > stored is stale', () {
    expect(isCasStale(baseVersion: 2, currentVersion: 1), isTrue);
    expect(isCasStale(baseVersion: 1, currentVersion: 1), isFalse);
    expect(isCasStale(baseVersion: 0, currentVersion: 5), isFalse);
  });
}
