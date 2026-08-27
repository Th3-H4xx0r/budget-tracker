import { DataTypes, QueryInterface, Transaction } from 'sequelize';

/**
 * `20260826000000-create-future-budget-planner.ts` already ran in some environments before
 * `autoAddSyncedTransactions` was added to it, so that edit alone never reaches those databases —
 * Sequelize tracks completed migrations by filename and won't re-run one already marked applied.
 * This migration adds the column for any environment where it's still missing.
 */
module.exports = {
  up: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      const table = await queryInterface.describeTable('FutureBudgetPlans');

      if (!table.autoAddSyncedTransactions) {
        await queryInterface.addColumn(
          'FutureBudgetPlans',
          'autoAddSyncedTransactions',
          {
            type: DataTypes.BOOLEAN,
            allowNull: false,
            defaultValue: false,
          },
          { transaction: t },
        );
      }

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },

  down: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      await queryInterface.removeColumn('FutureBudgetPlans', 'autoAddSyncedTransactions', { transaction: t });

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },
};
