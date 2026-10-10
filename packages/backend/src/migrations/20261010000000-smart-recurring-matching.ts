import { DataTypes, QueryInterface, Transaction } from 'sequelize';

const SUGGESTIONS_TABLE = 'SubscriptionMatchSuggestions';
const SUGGESTIONS_USER_STATUS_INDEX = 'subscription_match_suggestions_user_status_idx';
const SUGGESTIONS_TRANSACTION_INDEX = 'subscription_match_suggestions_transaction_idx';
const PLAN_ENTRY_TRANSACTION_UNIQUE_INDEX = 'future_budget_entries_plan_transaction_unique';

/**
 * Noise tokens dropped when deriving a merchant key. A frozen copy of `MERCHANT_NOISE_TOKENS` in
 * `services/subscriptions/matching/merchant-key.ts`: migrations never import app code, so later edits
 * to the helper don't change what this backfill computed.
 */
const MERCHANT_NOISE_TOKENS = [
  'pos',
  'purchase',
  'card',
  'visa',
  'mastercard',
  'mc',
  'debit',
  'credit',
  'payment',
  'pmt',
  'recurring',
  'rec',
  'txn',
  'ref',
  'online',
  'www',
  'com',
  'net',
  'org',
  'inc',
  'ltd',
  'llc',
  'gmbh',
  'sa',
  'bv',
];

/**
 * Schema for smart recurring-payment matching, discovery and planned-budget sync.
 *
 * - `SubscriptionMatchSuggestions`: one row per (subscription, transaction) pair the scoring matcher or
 *   discovery proposed. `status = 'dismissed'` is the user's "Not this one" memory and blocks the pair
 *   from being suggested or auto-linked again.
 * - `SubscriptionTransactions.matchScore` / `matchReasons`: set on links the scoring matcher created;
 *   null on manual links.
 * - `SubscriptionCandidates`: discovery dedupes on `merchantKey` (+ `transactionType`, `currencyCode`)
 *   instead of `suggestedName`. Existing candidates were all expense clusters, hence the `expense`
 *   default. `merchantKey` is backfilled from `suggestedName` with a SQL port of `buildMerchantKey`
 *   (minus diacritic folding).
 * - `FutureBudgetEntries.transactionId` / `subscriptionId`: an auto-added entry points at the real
 *   transaction it mirrors and the recurring payment that transaction is linked to, so plan sync can
 *   upsert idempotently on `(planId, transactionId)` and the plan view can count a paid occurrence once.
 *
 * Status, source and type columns are VARCHAR (no DB enums); their values live in TS enums in
 * `@bt/shared/types`. `Transactions` is untouched, so the `real_transactions` view needs no rebuild.
 */
module.exports = {
  up: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      await queryInterface.createTable(
        SUGGESTIONS_TABLE,
        {
          subscriptionId: {
            type: DataTypes.UUID,
            allowNull: false,
            primaryKey: true,
            references: { model: 'Subscriptions', key: 'id' },
            onUpdate: 'CASCADE',
            onDelete: 'CASCADE',
          },
          transactionId: {
            type: DataTypes.UUID,
            allowNull: false,
            primaryKey: true,
            references: { model: 'Transactions', key: 'id' },
            onUpdate: 'CASCADE',
            onDelete: 'CASCADE',
          },
          userId: {
            type: DataTypes.INTEGER,
            allowNull: false,
            references: { model: 'Users', key: 'id' },
            onUpdate: 'CASCADE',
            onDelete: 'CASCADE',
          },
          score: {
            type: DataTypes.REAL,
            allowNull: false,
          },
          reasons: {
            type: DataTypes.JSONB,
            allowNull: false,
            defaultValue: [],
          },
          status: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: 'pending',
          },
          source: {
            type: DataTypes.STRING(20),
            allowNull: false,
            defaultValue: 'engine',
          },
          createdAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
          },
          updatedAt: {
            type: DataTypes.DATE,
            allowNull: false,
            defaultValue: DataTypes.NOW,
          },
        },
        { transaction: t },
      );

      await queryInterface.addIndex(SUGGESTIONS_TABLE, ['userId', 'status'], {
        name: SUGGESTIONS_USER_STATUS_INDEX,
        transaction: t,
      });
      await queryInterface.addIndex(SUGGESTIONS_TABLE, ['transactionId'], {
        name: SUGGESTIONS_TRANSACTION_INDEX,
        transaction: t,
      });

      await queryInterface.addColumn(
        'SubscriptionTransactions',
        'matchScore',
        { type: DataTypes.REAL, allowNull: true, defaultValue: null },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionTransactions',
        'matchReasons',
        { type: DataTypes.JSONB, allowNull: true, defaultValue: null },
        { transaction: t },
      );

      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'merchantKey',
        { type: DataTypes.STRING(200), allowNull: true },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'transactionType',
        { type: DataTypes.STRING(50), allowNull: false, defaultValue: 'expense' },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'amountVariability',
        { type: DataTypes.REAL, allowNull: true },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'detectionSource',
        { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'heuristic' },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'aiReason',
        { type: DataTypes.TEXT, allowNull: true },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'aiFingerprint',
        { type: DataTypes.STRING(64), allowNull: true },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'SubscriptionCandidates',
        'nextExpectedDate',
        { type: DataTypes.DATEONLY, allowNull: true },
        { transaction: t },
      );

      // Tokens: lowercase, non-alphanumerics to spaces. Dropped: noise words, single characters, tokens
      // with 4+ digits, and tokens mixing letters with 3+ digits. Key: first three distinct survivors.
      await queryInterface.sequelize.query(
        `UPDATE "SubscriptionCandidates" AS c
            SET "merchantKey" = NULLIF(k.key, '')
           FROM (
             SELECT sc.id,
                    array_to_string(ARRAY(
                      SELECT kept.tok
                        FROM (
                          SELECT DISTINCT ON (tok) tok, ord
                            FROM unnest(string_to_array(
                                   btrim(regexp_replace(lower(sc."suggestedName"), '[^[:alnum:]]+', ' ', 'g')),
                                   ' '
                                 )) WITH ORDINALITY AS tokens(tok, ord)
                           WHERE length(tok) > 1
                             AND tok NOT IN (:noiseTokens)
                             AND length(regexp_replace(tok, '[^0-9]', '', 'g')) < 4
                             AND NOT (tok ~ '[^0-9]' AND length(regexp_replace(tok, '[^0-9]', '', 'g')) >= 3)
                           ORDER BY tok, ord
                        ) AS kept
                       ORDER BY kept.ord
                       LIMIT 3
                    ), ' ') AS key
               FROM "SubscriptionCandidates" AS sc
           ) AS k
          WHERE c.id = k.id;`,
        { transaction: t, replacements: { noiseTokens: MERCHANT_NOISE_TOKENS } },
      );

      await queryInterface.addColumn(
        'FutureBudgetEntries',
        'transactionId',
        {
          type: DataTypes.UUID,
          allowNull: true,
          references: { model: 'Transactions', key: 'id' },
          onUpdate: 'CASCADE',
          onDelete: 'CASCADE',
        },
        { transaction: t },
      );
      await queryInterface.addColumn(
        'FutureBudgetEntries',
        'subscriptionId',
        {
          type: DataTypes.UUID,
          allowNull: true,
          references: { model: 'Subscriptions', key: 'id' },
          onUpdate: 'CASCADE',
          onDelete: 'SET NULL',
        },
        { transaction: t },
      );
      await queryInterface.sequelize.query(
        `CREATE UNIQUE INDEX "${PLAN_ENTRY_TRANSACTION_UNIQUE_INDEX}"
           ON "FutureBudgetEntries" ("planId", "transactionId")
           WHERE "transactionId" IS NOT NULL;`,
        { transaction: t },
      );

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },

  down: async (queryInterface: QueryInterface): Promise<void> => {
    const t: Transaction = await queryInterface.sequelize.transaction();

    try {
      await queryInterface.sequelize.query(`DROP INDEX IF EXISTS "${PLAN_ENTRY_TRANSACTION_UNIQUE_INDEX}";`, {
        transaction: t,
      });
      await queryInterface.removeColumn('FutureBudgetEntries', 'subscriptionId', { transaction: t });
      await queryInterface.removeColumn('FutureBudgetEntries', 'transactionId', { transaction: t });

      for (const column of [
        'nextExpectedDate',
        'aiFingerprint',
        'aiReason',
        'detectionSource',
        'amountVariability',
        'transactionType',
        'merchantKey',
      ]) {
        await queryInterface.removeColumn('SubscriptionCandidates', column, { transaction: t });
      }

      await queryInterface.removeColumn('SubscriptionTransactions', 'matchReasons', { transaction: t });
      await queryInterface.removeColumn('SubscriptionTransactions', 'matchScore', { transaction: t });

      await queryInterface.dropTable(SUGGESTIONS_TABLE, { transaction: t });

      await t.commit();
    } catch (error) {
      await t.rollback();
      throw error;
    }
  },
};
