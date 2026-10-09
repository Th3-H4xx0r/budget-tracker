import { DataTypes, QueryInterface, Transaction } from 'sequelize';

import { createRealTransactionsViewSql, dropRealTransactionsViewSql } from './utils/real-transactions-view';

const REVIEW_QUEUE_INDEX = 'transactions_review_queue_idx';

/**
 * Adds the Transaction Review label. `reviewStatus` is VARCHAR (no DB enums); the values live in
 * `TRANSACTION_REVIEW_STATUS`. `reviewDeferredAt` is set by "Check later" and orders deferred rows
 * behind fresh ones.
 *
 * The partial index matches the queue's sort (`"reviewDeferredAt" ASC NULLS FIRST, "time" ASC`)
 * so the review card stack and the Unreviewed tab read it in index order.
 *
 * The backfill puts the last 30 days of synced and imported real transactions into the queue,
 * using the same rule `createTransaction` applies to new rows. Rows a bank sync or import merged
 * into a planned transaction (`externalData.plannedMerge`) stay `not_required`, because the user
 * created the plan.
 */
module.exports = {
  up: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      await queryInterface.addColumn(
        'Transactions',
        'reviewStatus',
        {
          type: DataTypes.STRING(20),
          allowNull: false,
          defaultValue: 'not_required',
        },
        { transaction: t },
      );

      await queryInterface.addColumn(
        'Transactions',
        'reviewDeferredAt',
        {
          type: DataTypes.DATE,
          allowNull: true,
          defaultValue: null,
        },
        { transaction: t },
      );

      await queryInterface.sequelize.query(
        `UPDATE "Transactions"
            SET "reviewStatus" = 'unreviewed'
          WHERE "isPlanned" = false
            AND "time" >= NOW() - INTERVAL '30 days'
            AND ("accountType" <> 'system' OR "externalData" -> 'importDetails' IS NOT NULL)
            AND "externalData" -> 'plannedMerge' IS NULL;`,
        { transaction: t },
      );

      // Built after the backfill so the index is created in one pass instead of maintained per row.
      await queryInterface.sequelize.query(
        `CREATE INDEX "${REVIEW_QUEUE_INDEX}"
           ON "Transactions" ("userId", "reviewDeferredAt" ASC NULLS FIRST, "time" ASC)
           WHERE "reviewStatus" = 'unreviewed';`,
        { transaction: t },
      );

      await queryInterface.sequelize.query(createRealTransactionsViewSql, { transaction: t });

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },

  down: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      await queryInterface.sequelize.query(dropRealTransactionsViewSql, { transaction: t });

      await queryInterface.sequelize.query(`DROP INDEX IF EXISTS "${REVIEW_QUEUE_INDEX}";`, { transaction: t });

      await queryInterface.removeColumn('Transactions', 'reviewDeferredAt', { transaction: t });
      await queryInterface.removeColumn('Transactions', 'reviewStatus', { transaction: t });

      await queryInterface.sequelize.query(createRealTransactionsViewSql, { transaction: t });

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },
};
