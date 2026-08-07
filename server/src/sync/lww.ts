/**
 * Canonical conflict resolution (docs/BACKEND_API.md §4) — pure and
 * deterministic so the server and every client converge on the same winner:
 *
 *   1. Highest `version` wins.
 *   2. Version equal → newest `updated_at` wins.
 *   3. Still equal → lexicographically smallest `opId` wins.
 */
export interface LwwCandidate {
  version: number;
  updatedAt: Date;
  opId: string;
}

export function lwwWinner(current: LwwCandidate, incoming: LwwCandidate): 'current' | 'incoming' {
  if (incoming.version > current.version) return 'incoming';
  if (incoming.version < current.version) return 'current';
  if (incoming.updatedAt.getTime() > current.updatedAt.getTime()) return 'incoming';
  if (incoming.updatedAt.getTime() < current.updatedAt.getTime()) return 'current';
  // Tie-break: smallest opId wins (both are UUIDs — stable string compare).
  return incoming.opId < current.opId ? 'incoming' : 'current';
}
