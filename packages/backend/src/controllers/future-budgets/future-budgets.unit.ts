import { SUBSCRIPTION_LINK_STATUS } from '@bt/shared/types';
import Transactions from '@models/transactions.model';

import { realBankRecurringTransactionsInclude } from './future-budgets';

describe('realBankRecurringTransactionsInclude', () => {
  it('uses the subscription transactions association and excludes planned transactions', () => {
    expect(realBankRecurringTransactionsInclude()).toMatchObject({
      model: Transactions,
      required: true,
      where: { isPlanned: false },
      through: {
        attributes: [],
        where: { status: SUBSCRIPTION_LINK_STATUS.active },
      },
    });
  });
});
