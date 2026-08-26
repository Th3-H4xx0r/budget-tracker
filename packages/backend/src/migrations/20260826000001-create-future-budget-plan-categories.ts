import { DataTypes, QueryInterface } from 'sequelize';

module.exports = {
  up: async (queryInterface: QueryInterface): Promise<void> => {
    await queryInterface.createTable('FutureBudgetPlanCategories', {
      planId: {
        type: DataTypes.UUID,
        primaryKey: true,
        allowNull: false,
        references: { model: 'FutureBudgetPlans', key: 'id' },
        onDelete: 'CASCADE',
      },
      categoryId: {
        type: DataTypes.UUID,
        primaryKey: true,
        allowNull: false,
        references: { model: 'Categories', key: 'id' },
        onDelete: 'CASCADE',
      },
    });
  },
  down: async (queryInterface: QueryInterface): Promise<void> => queryInterface.dropTable('FutureBudgetPlanCategories'),
};
