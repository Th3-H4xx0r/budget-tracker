import { TRANSACTION_TRANSFER_NATURE, TRANSACTION_TYPES, type TransactionModel } from '@bt/shared/types';
import { describe, expect, it } from 'vitest';

import { useTransactionsDisplay } from './use-transactions-display';

const makeTransferLeg = ({ id, transactionType }: { id: string; transactionType: TRANSACTION_TYPES }) =>
  ({
    id,
    transactionType,
    transferNature: TRANSACTION_TRANSFER_NATURE.common_transfer,
    transferId: 'transfer-1',
    time: '2026-10-01T10:00:00.000Z',
  }) as unknown as TransactionModel;

const transferLegs = [
  makeTransferLeg({ id: 'expense-leg', transactionType: TRANSACTION_TYPES.expense }),
  makeTransferLeg({ id: 'income-leg', transactionType: TRANSACTION_TYPES.income }),
];

const displayedIds = ({ disableTransferDedup }: { disableTransferDedup?: boolean }) => {
  const { displayTransactions } = useTransactionsDisplay({ transactions: transferLegs, disableTransferDedup });
  return displayTransactions.value.map((item) => (item as TransactionModel).id);
};

describe('useTransactionsDisplay transfer dedup', () => {
  it('shows only the expense leg when both legs are listed', () => {
    expect(displayedIds({})).toEqual(['expense-leg']);
  });

  it('keeps both legs when dedup is disabled', () => {
    expect(displayedIds({ disableTransferDedup: true })).toEqual(['expense-leg', 'income-leg']);
  });
});
