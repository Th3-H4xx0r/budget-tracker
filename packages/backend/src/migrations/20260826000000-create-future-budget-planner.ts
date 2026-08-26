import { DataTypes, QueryInterface } from 'sequelize';

module.exports = {
  up: async (queryInterface: QueryInterface): Promise<void> => {
    await queryInterface.sequelize.transaction(async (transaction) => {
      await queryInterface.createTable(
        'FutureBudgetSettings',
        {
          userId: {
            type: DataTypes.INTEGER,
            primaryKey: true,
            references: { model: 'Users', key: 'id' },
            onDelete: 'CASCADE',
          },
          salaryAmount: { type: DataTypes.BIGINT, allowNull: false, defaultValue: 0 },
          salaryFrequency: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'monthly' },
          salaryIntervalDays: { type: DataTypes.INTEGER, allowNull: true },
          salaryAnchorDate: { type: DataTypes.DATEONLY, allowNull: true },
          salaryCategoryId: {
            type: DataTypes.UUID,
            allowNull: true,
            references: { model: 'Categories', key: 'id' },
            onDelete: 'SET NULL',
          },
          revision: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 1 },
          createdAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
          updatedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
        },
        { transaction },
      );
      await queryInterface.createTable(
        'FutureBudgetPlans',
        {
          id: { type: DataTypes.UUID, primaryKey: true, allowNull: false },
          userId: {
            type: DataTypes.INTEGER,
            allowNull: false,
            references: { model: 'Users', key: 'id' },
            onDelete: 'CASCADE',
          },
          name: { type: DataTypes.STRING(200), allowNull: false },
          type: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'manual' },
          status: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'active' },
          startDate: { type: DataTypes.DATEONLY, allowNull: false },
          endDate: { type: DataTypes.DATEONLY, allowNull: false },
          salaryAmount: { type: DataTypes.BIGINT, allowNull: false, defaultValue: 0 },
          salaryFrequency: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'monthly' },
          salaryIntervalDays: { type: DataTypes.INTEGER, allowNull: true },
          salaryAnchorDate: { type: DataTypes.DATEONLY, allowNull: true },
          salaryCategoryId: {
            type: DataTypes.UUID,
            allowNull: true,
            references: { model: 'Categories', key: 'id' },
            onDelete: 'SET NULL',
          },
          salaryProfileRevision: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 1 },
          dismissedSalaryProfileRevision: { type: DataTypes.INTEGER, allowNull: true },
          createdAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
          updatedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
        },
        { transaction },
      );
      await queryInterface.createTable(
        'FutureBudgetEntries',
        {
          id: { type: DataTypes.UUID, primaryKey: true, allowNull: false },
          planId: {
            type: DataTypes.UUID,
            allowNull: false,
            references: { model: 'FutureBudgetPlans', key: 'id' },
            onDelete: 'CASCADE',
          },
          transactionType: { type: DataTypes.STRING(20), allowNull: false },
          amount: { type: DataTypes.BIGINT, allowNull: false },
          date: { type: DataTypes.DATEONLY, allowNull: false },
          categoryId: {
            type: DataTypes.UUID,
            allowNull: true,
            references: { model: 'Categories', key: 'id' },
            onDelete: 'SET NULL',
          },
          note: { type: DataTypes.TEXT, allowNull: true },
          frequency: { type: DataTypes.STRING(20), allowNull: true },
          intervalDays: { type: DataTypes.INTEGER, allowNull: true },
          createdAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
          updatedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
        },
        { transaction },
      );
      await queryInterface.createTable(
        'FutureBudgetRecurringOverrides',
        {
          id: { type: DataTypes.UUID, primaryKey: true, allowNull: false },
          planId: {
            type: DataTypes.UUID,
            allowNull: false,
            references: { model: 'FutureBudgetPlans', key: 'id' },
            onDelete: 'CASCADE',
          },
          subscriptionId: {
            type: DataTypes.UUID,
            allowNull: false,
            references: { model: 'Subscriptions', key: 'id' },
            onDelete: 'CASCADE',
          },
          isIncluded: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true },
          amount: { type: DataTypes.BIGINT, allowNull: true },
          categoryId: {
            type: DataTypes.UUID,
            allowNull: true,
            references: { model: 'Categories', key: 'id' },
            onDelete: 'SET NULL',
          },
          nextOccurrenceDate: { type: DataTypes.DATEONLY, allowNull: true },
          createdAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
          updatedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
        },
        { transaction },
      );
      await queryInterface.addIndex('FutureBudgetPlans', ['userId', 'startDate', 'endDate'], { transaction });
      await queryInterface.addIndex('FutureBudgetEntries', ['planId', 'date'], { transaction });
      await queryInterface.addIndex('FutureBudgetRecurringOverrides', ['planId', 'subscriptionId'], {
        unique: true,
        transaction,
      });
    });
  },
  down: async (queryInterface: QueryInterface): Promise<void> => {
    await queryInterface.sequelize.transaction(async (transaction) => {
      await queryInterface.dropTable('FutureBudgetEntries', { transaction });
      await queryInterface.dropTable('FutureBudgetRecurringOverrides', { transaction });
      await queryInterface.dropTable('FutureBudgetPlans', { transaction });
      await queryInterface.dropTable('FutureBudgetSettings', { transaction });
    });
  },
};
