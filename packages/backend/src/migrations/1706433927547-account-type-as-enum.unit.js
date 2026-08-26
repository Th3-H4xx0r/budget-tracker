const migration = require('./1706433927547-account-type-as-enum');

describe('1706433927547-account-type-as-enum migration', () => {
  it('removes the legacy Monobank account-type foreign key before dropping AccountTypes', async () => {
    const transaction = { commit: jest.fn(), rollback: jest.fn() };
    const queryInterface = {
      sequelize: {
        transaction: jest.fn().mockResolvedValue(transaction),
        query: jest.fn().mockResolvedValue(undefined),
      },
      addColumn: jest.fn().mockResolvedValue(undefined),
      removeColumn: jest.fn().mockResolvedValue(undefined),
      tableExists: jest.fn().mockResolvedValue(true),
      getForeignKeyReferencesForTable: jest.fn().mockResolvedValue([
        {
          constraintName: 'MonobankAccounts_accountTypeId_fkey',
          columnName: 'accountTypeId',
          referencedTableName: 'AccountTypes',
        },
      ]),
      removeConstraint: jest.fn().mockResolvedValue(undefined),
      dropTable: jest.fn().mockResolvedValue(undefined),
    };

    await migration.up(queryInterface, { ENUM: jest.fn() });

    expect(queryInterface.removeConstraint).toHaveBeenCalledWith(
      'MonobankAccounts',
      'MonobankAccounts_accountTypeId_fkey',
      { transaction },
    );
    expect(queryInterface.removeConstraint.mock.invocationCallOrder[0]).toBeLessThan(
      queryInterface.dropTable.mock.invocationCallOrder[0],
    );
  });
});
