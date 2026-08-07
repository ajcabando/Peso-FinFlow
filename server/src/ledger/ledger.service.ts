import { Injectable, NotFoundException } from '@nestjs/common';
import { and, eq, isNull } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { accounts, ledgerEntries, transactions } from '../drizzle/schema';

/**
 * Balances are ALWAYS derived from `ledger_entries` — never stored. A balance
 * is the sum of all entry amounts for an account: debits add, credits subtract
 * (matching the app's double-entry convention where an expense debits its
 * category account and credits the payment account).
 */
@Injectable()
export class LedgerService {
  constructor(private readonly database: DatabaseService) {}

  async accountBalance(userId: string, accountId: string): Promise<{
    accountId: string;
    balanceMinor: number;
    currencyCode: string;
    asOf: string;
  }> {
    const [account] = await this.database.db
      .select({ id: accounts.id, currencyCode: accounts.currencyCode })
      .from(accounts)
      .where(and(eq(accounts.userId, userId), eq(accounts.id, accountId)));
    if (!account) throw new NotFoundException('Account not found');

    // Only entries of NON-deleted transactions count — the materializer
    // hard-deletes a soft-deleted transaction's entries, so a simple sum over
    // live ledger_entries is already correct. The isNull join is belt-and-
    // braces for any row that slipped through.
    const rows = await this.database.db
      .select({
        direction: ledgerEntries.direction,
        amountMinor: ledgerEntries.amountMinor,
      })
      .from(ledgerEntries)
      .innerJoin(
        transactions,
        and(
          eq(transactions.userId, ledgerEntries.userId),
          eq(transactions.id, ledgerEntries.transactionId),
        ),
      )
      .where(
        and(
          eq(ledgerEntries.userId, userId),
          eq(ledgerEntries.accountId, accountId),
          isNull(transactions.deletedAt),
        ),
      );

    let balanceMinor = 0;
    for (const row of rows) {
      balanceMinor += row.direction === 'debit' ? row.amountMinor : -row.amountMinor;
    }

    return {
      accountId,
      balanceMinor,
      currencyCode: account.currencyCode,
      asOf: new Date().toISOString(),
    };
  }

  async transactionEntries(userId: string, transactionId: string): Promise<{
    transactionId: string;
    entries: {
      id: string;
      accountId: string;
      direction: 'debit' | 'credit';
      amountMinor: number;
      currencyCode: string;
    }[];
  }> {
    const [txn] = await this.database.db
      .select({ id: transactions.id })
      .from(transactions)
      .where(
        and(
          eq(transactions.userId, userId),
          eq(transactions.id, transactionId),
          isNull(transactions.deletedAt),
        ),
      );
    if (!txn) throw new NotFoundException('Transaction not found');

    const rows = await this.database.db
      .select()
      .from(ledgerEntries)
      .where(
        and(
          eq(ledgerEntries.userId, userId),
          eq(ledgerEntries.transactionId, transactionId),
        ),
      );

    return {
      transactionId,
      entries: rows.map((r) => ({
        id: r.id,
        accountId: r.accountId,
        direction: r.direction as 'debit' | 'credit',
        amountMinor: r.amountMinor,
        currencyCode: r.currencyCode,
      })),
    };
  }
}
