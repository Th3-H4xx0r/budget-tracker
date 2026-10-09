import type { ExtractedTransaction, StatementDuplicateMatch } from '@bt/shared/types';
import { asCents } from '@bt/shared/types';
import { Money } from '@common/types/money';
import {
  type TransactionToCheck,
  detectDuplicates as genericDetectDuplicates,
} from '@root/services/transactions/duplicates-detection/detect-duplicates.service';

interface DetectDuplicatesParams {
  userId: number;
  accountId: string;
  transactions: ExtractedTransaction[];
}

/**
 * Detect duplicate transactions for statement import.
 *
 * This is a wrapper around the generic detectDuplicates service, which compares
 * amounts in cents. Extracted amounts arrive as decimals, so they are converted
 * to cents for matching, while the response echoes each extracted transaction
 * exactly as sent and reports the existing transaction's amount as a decimal.
 */
export async function detectDuplicates({
  userId,
  accountId,
  transactions,
}: DetectDuplicatesParams): Promise<StatementDuplicateMatch[]> {
  const transactionsToCheck: TransactionToCheck[] = transactions.map((tx) => ({
    date: tx.date,
    amount: asCents(Money.fromDecimal(tx.amount).toCents()),
    type: tx.type,
  }));

  const duplicates = await genericDetectDuplicates({
    userId,
    accountId,
    transactions: transactionsToCheck,
  });

  return duplicates.map((d) => ({
    transactionIndex: d.index,
    extractedTransaction: transactions[d.index]!,
    existingTransaction: {
      ...d.existing,
      amount: Money.fromCents(d.existing.amount).toNumber(),
    },
  }));
}
