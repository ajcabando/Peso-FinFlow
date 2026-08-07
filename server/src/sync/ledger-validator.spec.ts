import { HttpException } from '@nestjs/common';
import { assertBalancedLedger } from './ledger-validator';

const balanced = {
  id: 'txn-1',
  type: 'expense',
  amount_minor: 50000,
  currency_code: 'PHP',
  ledgerEntries: [
    { id: 'e1', account_id: 'cash', direction: 'credit', amount_minor: 50000, currency_code: 'PHP' },
    { id: 'e2', account_id: 'food', direction: 'debit', amount_minor: 50000, currency_code: 'PHP' },
  ],
};

describe('assertBalancedLedger (server-side double-entry invariant)', () => {
  it('accepts a balanced two-entry ledger', () => {
    expect(() => assertBalancedLedger(balanced)).not.toThrow();
  });

  it('rejects a single entry', () => {
    const bad = { ...balanced, ledgerEntries: [balanced.ledgerEntries[0]] };
    expect(() => assertBalancedLedger(bad)).toThrow(HttpException);
  });

  it('rejects unbalanced debits/credits', () => {
    const bad = {
      ...balanced,
      ledgerEntries: [
        { ...balanced.ledgerEntries[0] }, // credit 50000
        { ...balanced.ledgerEntries[1], amount_minor: 40000 }, // debit 40000
      ],
    };
    try {
      assertBalancedLedger(bad);
      fail('expected imbalance to throw');
    } catch (e) {
      expect(e).toBeInstanceOf(HttpException);
      expect((e as HttpException).getStatus()).toBe(409);
      expect((e as HttpException).getResponse()).toMatchObject({
        code: 'LEDGER_IMBALANCE',
      });
    }
  });

  it('rejects non-positive or fractional amounts', () => {
    for (const amount of [0, -5, 12.5]) {
      const bad = {
        ...balanced,
        ledgerEntries: [
          { ...balanced.ledgerEntries[0], amount_minor: amount },
          { ...balanced.ledgerEntries[1] },
        ],
      };
      expect(() => assertBalancedLedger(bad)).toThrow(HttpException);
    }
  });

  it('rejects unknown directions', () => {
    const bad = {
      ...balanced,
      ledgerEntries: [
        { ...balanced.ledgerEntries[0], direction: 'sideways' },
        { ...balanced.ledgerEntries[1] },
      ],
    };
    expect(() => assertBalancedLedger(bad)).toThrow(HttpException);
  });

  it('rejects a missing ledgerEntries array', () => {
    const bad = { id: 'txn-2', type: 'expense' };
    expect(() => assertBalancedLedger(bad)).toThrow(HttpException);
  });

  it('accepts a multi-entry balanced ledger (3+ entries)', () => {
    const multi = {
      ...balanced,
      ledgerEntries: [
        { ...balanced.ledgerEntries[0], amount_minor: 20000 },
        { ...balanced.ledgerEntries[1], amount_minor: 20000 },
        { ...balanced.ledgerEntries[0], amount_minor: 20000 },
        { ...balanced.ledgerEntries[1], amount_minor: 20000 },
      ],
    };
    expect(() => assertBalancedLedger(multi)).not.toThrow();
  });
});
