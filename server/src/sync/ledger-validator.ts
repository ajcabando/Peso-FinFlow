import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Mirrors the client's `DoubleEntryEngine` invariants for transaction ops:
 * ≥ 2 entries, positive integer amounts, valid debit/credit directions and
 * debits == credits. A violating payload is rejected with 409 and the
 * `LEDGER_IMBALANCE` code — the server never stores an unbalanced ledger.
 */
export function assertBalancedLedger(payload: Record<string, unknown>): void {
  const entries = payload['ledgerEntries'];
  if (!Array.isArray(entries) || entries.length < 2) {
    throw imbalance(
      'Transaction payload must include at least 2 ledger entries',
    );
  }

  let debits = 0;
  let credits = 0;
  for (const entry of entries) {
    if (typeof entry !== 'object' || entry === null) {
      throw imbalance('Every ledger entry must be an object');
    }
    const e = entry as Record<string, unknown>;
    if (e['direction'] !== 'debit' && e['direction'] !== 'credit') {
      throw imbalance('Every ledger entry needs direction "debit" or "credit"');
    }
    const amount = e['amount_minor'];
    if (
      typeof amount !== 'number' ||
      !Number.isInteger(amount) ||
      amount <= 0 ||
      amount > Number.MAX_SAFE_INTEGER
    ) {
      throw imbalance(
        'Every ledger entry needs a positive integer amount_minor (within the safe integer range)',
      );
    }
    if (e['direction'] === 'debit') debits += amount;
    else credits += amount;
  }

  if (debits !== credits) {
    throw imbalance(
      `Ledger must balance: debits (${debits}) do not equal credits (${credits})`,
    );
  }
}

function imbalance(message: string): HttpException {
  return new HttpException(
    { code: 'LEDGER_IMBALANCE', message },
    HttpStatus.CONFLICT,
  );
}
